# Hub 内网 DNS（阶段 G2）

在 Hub `10.200.0.1`（wg0）上运行 **dnsmasq**，为 WireGuard 内网提供 `*.internal` 解析。

**状态（实施前）**：`internal_dns.enabled: true`，`internal_dns.status: not_started`（apply 后改为 `operational`）。

## 解析表

| 域名 | 地址 | 说明 |
|------|------|------|
| `hub.internal` | 10.200.0.1 | Hub / Nginx |
| `jms.internal` | 10.200.0.1 | JumpServer（Nginx 反代） |
| `ci.internal` | 10.200.0.2 | CI / dev-01 同机 |
| `dev-app.internal` | 10.200.0.2 | Dev 应用（待部署） |
| `dev-02.internal` | 10.200.1.2 | Dev-02 预留 |
| `test-app.internal` | 10.200.2.1 | Test 预留 |

变量 SSOT：`ansible/inventories/mgmt/group_vars/all/internal_dns.yml`

## 安全组

Hub 须在 **pending_inbound → IN-DNS-WG** 于控制台落地后 apply：UDP 53 ← `10.200.0.0/16`（见 `docs/security-groups/hub-wg.rules.yaml`）。

## 实施步骤（ci-01）

```bash
cd ~/infra-ops
chmod +x scripts/mgmt/stage-g2-preflight.sh

# 1. 控制台添加 IN-DNS-WG 后
make stage-g2-preflight

export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy
export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass

# 2. Hub G2：dnsmasq + Nginx JumpServer 细化
ansible-playbook ansible/playbooks/hub-g2.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass

# 3. 刷新 ci-01 WG Client（写入 DNS=10.200.0.1）
ansible-playbook ansible/playbooks/wireguard-peer.yml \
  -i ansible/inventories/mgmt/ \
  --limit ci-01 \
  --vault-password-file .vault_pass

# 4. 更新 inventory
#    internal_dns.status: operational
#    docs/assets/hub-01.yaml → stage_g2_internal_dns

make inventory-mgmt
```

## 笔记本 WG Client

在 `[Interface]` 增加（或重载配置）：

```ini
DNS = 10.200.0.1
```

然后：

```bash
sudo wg-quick down wg0 && sudo wg-quick up wg0
```

## 验收

```bash
# CI 或笔记本（须 WG 已连接）
dig @10.200.0.1 jms.internal +short
# 期望：10.200.0.1

curl -k https://jms.internal/jms/status
# 期望：JSON deploy_status=pending

curl -k -o /dev/null -w "%{http_code}\n" https://jms.internal/
# 期望：503（JumpServer 未部署）
```

验收报告：`docs/acceptance/20260616-阶段G2-Hub-DNS与JumpServer预留.md`

## 相关文件

| 路径 | 说明 |
|------|------|
| `ansible/playbooks/hub-g2.yml` | Playbook |
| `ansible/roles/dnsmasq/` | dnsmasq role |
| `ansible/roles/nginx/templates/hub-jms.conf.j2` | JumpServer 维护页 + /jms/status |
| `scripts/mgmt/stage-g2-preflight.sh` | 预检 |

## JumpServer 上线后（G3）

将 `nginx.jumpserver.deploy_status` 改为 `ready`，重新 `hub-g2.yml` 或 `nginx-hub.yml`，`jms.internal/` 将反代到 `127.0.0.1:8080`。
