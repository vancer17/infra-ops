# 管理面 Inventory（`inventories/mgmt/`）

Ansible 对 **Hub / 管理面** 的主机清单，与 `inventories/dev/` 分离。

**hub-01 状态（2026-06-16）**：Bootstrap + SSH（`ssh_done`）；阶段 F WireGuard `operational`；**阶段 G1 Nginx `operational`**；**阶段 G2 内网 DNS 待 apply**（`internal_dns.status: not_started`）。**下一步**：`hub-g2.yml` → JumpServer（G3）；**steady**：关公网 SSH / `IN-SSH-WG`。

## 用途

| 目录/文件 | 说明 |
|-----------|------|
| `hosts.yml` | 分组：`mgmt` → `mgmt_hub` → `hub-01`；`wireguard_peers` → `ci-01` |
| `host_vars/hub-01.yml` | 主机级 `ansible_host`（私网 / 公网 / WG 切换逻辑） |
| `host_vars/ci-01.yml` | ci-01 本机 WG Client（`ansible_connection: local`） |
| `group_vars/all/main.yml` | 环境标识、时区、`network_phase` |
| `group_vars/all/network.yml` | IP 台账、`ci_connectivity`、`mgmt_hosts` |
| `group_vars/all/ssh.yml` | SSH 用户与 CI 密钥路径 |
| `group_vars/all/bootstrap.yml` | Hub Bootstrap 参数（默认不装 Docker） |
| `group_vars/all/wireguard.yml` | WG 规划、`hub_public_key`、Peer 公钥 |
| `group_vars/all/wireguard_keys.yml` | 密钥路径与保管策略（无私钥） |
| `group_vars/all/nginx.yml` | Hub Nginx 网关（阶段 G1/G2） |
| `group_vars/all/internal_dns.yml` | Hub dnsmasq 内网 DNS（阶段 G2） |

## Playbooks（mgmt）

| Playbook | 用途 |
|----------|------|
| `ansible/playbooks/bootstrap.yml` | Hub Bootstrap（`-i mgmt/ --limit hub-01`） |
| `ansible/playbooks/wireguard-hub.yml` | 阶段 F1：Hub WireGuard Server |
| `ansible/playbooks/wireguard-peer.yml` | 阶段 F2：ci-01 WireGuard Client |
| `ansible/playbooks/nginx-hub.yml` | 阶段 G1：Hub 管理面 Nginx 网关 |
| `ansible/playbooks/hub-g2.yml` | 阶段 G2：内网 DNS + JumpServer upstream 细化 |

```bash
ansible-playbook ansible/playbooks/wireguard-hub.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass \
  --check --diff

ansible-playbook ansible/playbooks/wireguard-peer.yml \
  -i ansible/inventories/mgmt/ \
  --limit ci-01 \
  --vault-password-file .vault_pass \
  --check --diff
```

## 常用命令

```bash
# 查看分组树
ansible-inventory -i ansible/inventories/mgmt/ --graph

# 静态校验（本地；含 vault 时需 .vault_pass）
make inventory-mgmt

# WireGuard 密钥（Hub 私钥勿提交 Git）
./scripts/wireguard/wg-keys.sh all-hub
./scripts/wireguard/wg-keys.sh vault-encrypt-hub

# 阶段 F 前置：Hub deploy 免密 sudo
./scripts/mgmt/apply-hub-deploy-sudo.sh

# 阶段 F2 前置：ci-01 deploy-wireguard 受限 sudo
./scripts/mgmt/apply-ci-wireguard-sudo.sh

# Bootstrap Hub（已完成 2026-06-14；日常用 deploy 密钥）
export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
ansible hub-01 -m ping -u deploy --private-key=ansible/keys/infra-ci-deploy
```

Runbook：`docs/bootstrap/hub-01-bootstrap.runbook.md`  
WireGuard 密钥：`docs/wireguard/wg-keys.runbook.md`  
阶段 F 前预检：`make stage-f-preflight`（F3-1 已通过）  
阶段 F3 验收：`docs/wireguard/stage-f3-acceptance-runbook.md`  
阶段 G1 Nginx：`docs/nginx/hub-nginx.runbook.md`（`make stage-g1-nginx-preflight`）；验收：`docs/acceptance/20260615-阶段G1-Hub-Nginx验收.md`  
阶段 G2 内网 DNS：`docs/dns/hub-internal-dns.runbook.md`（`make stage-g2-preflight`）；验收：`docs/acceptance/20260616-阶段G2-Hub-DNS与JumpServer预留.md`

## 资产同步

修改 IP/角色后，须同步：

1. `docs/assets/hub-01.yaml`
2. `docs/assets/registry.yaml`
3. 本目录 `group_vars` / `host_vars`
4. `make inventory-mgmt`

## 与 dev inventory 的关系

- **dev**：`dev-01`、`dev-02` — 应用环境（`inventories/dev/`）
- **mgmt / mgmt_hub**：`hub-01` — WireGuard Server、未来 JumpServer
- **wireguard_peers**：`ci-01` — 本机 WG Client（`ansible_connection: local`）；与 `dev-01` 同 ECS，逻辑名分离
- **control_plane_hosts**（`network.yml`）：ci-01 控制面台账，与 `wireguard_peers/ci-01` 互补而非互斥
