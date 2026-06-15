# Hub JumpServer Compose 部署 Runbook（阶段 G4）

在 Hub（`10.200.0.1`）部署 JumpServer **jms_all** all-in-one 容器，经 Nginx `https://jms.internal/` 对外（仅 WG）。

## 前提

- 阶段 G3：`hub_docker.status=operational`
- 阶段 G2：`jms.internal` Nginx 预留 + dnsmasq
- `.vault_pass` 与 GitHub `ANSIBLE_VAULT_PASSWORD` 一致

## 1. 生成 Vault 密钥（首次）

```bash
cd ~/infra-ops
./scripts/mgmt/jumpserver-vault-init.sh
# 提交加密文件：ansible/inventories/mgmt/group_vars/all/jumpserver_vault.yml
```

## 2. 预检

```bash
make stage-g4-jumpserver-preflight
```

## 3. 部署

```bash
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy
export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass

ansible-playbook ansible/playbooks/hub-g4-jumpserver.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass
```

首次启动可能需 **3～6 分钟**（内置数据库初始化）。

## 4. 验收

```bash
./scripts/mgmt/verify-hub-jumpserver-remote.sh

curl -k -s https://jms.internal/jms/status | python3 -m json.tool
# deploy_status 应为 ready

curl -k -o /dev/null -w "%{http_code}\n" https://jms.internal/
# 期望 200 或 302（登录页），不再是 503
```

## 5. 更新 Inventory（提交 Git）

**重要**：G4 apply 后须**立即**更新 inventory 并提交。若 `deploy_status` 仍为 `pending` 却重跑 `nginx-hub.yml` 或 `hub-g2.yml`，Hub Nginx 会将 `jms.internal` 切回 **503**（playbook 已加门禁：8080 已监听或 `jumpserver.status=operational` 时会失败并提示）。

`ansible/inventories/mgmt/group_vars/all/jumpserver.yml`：

```yaml
jumpserver:
  status: operational
```

`ansible/inventories/mgmt/group_vars/all/nginx.yml`：

```yaml
  jumpserver:
    deploy_status: ready
```

同步 `docs/assets/hub-01.yaml` → `jumpserver_status: operational`。

```bash
make inventory-mgmt
make ci
```

## 6. 首次登录

- URL：`https://jms.internal/`
- 默认用户：`admin`
- 默认密码：`ChangeMe`（**登录后立即修改**）

## 镜像

轩辕专属前缀（免交互鉴权）：

`5yrqsf19ms2mh4.xuanyuan.run/jumpserver/jms_all:v4.10.16`

升级：修改 `jumpserver.image_tag` 后重跑 `hub-g4-jumpserver.yml`。

## 架构

```text
WG Client → https://jms.internal:443 (Hub Nginx)
         → http://127.0.0.1:8080 (jms_all 容器)
```

容器 SSH（Koko）首期绑定 `127.0.0.1:2222`；资产纳管与公网 SSH 收口见后续堡垒机配置文档。
