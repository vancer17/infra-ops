# Ansible 密钥目录

SSH（阶段 1.3）与 WireGuard（Hub/Peer）密钥分目录存放。

## SSH — Dev ECS（`infra-ci-deploy*`）

| 文件 | 是否提交 Git | 说明 |
|------|--------------|------|
| `infra-ci-deploy` | **否**（gitignore） | CI/Ansible 私钥；复制到 GitHub Secret `ANSIBLE_SSH_PRIVATE_KEY` |
| `infra-ci-deploy.pub` | **是** | deploy 用户 authorized_keys 来源 |
| `infra-ci-deploy.pub.example` | 是 | 格式示例 |

在 CI 替代机（`121.41.58.20`）执行：

```bash
chmod +x scripts/dev/ssh-keys.sh
./scripts/dev/ssh-keys.sh generate
git add ansible/keys/infra-ci-deploy.pub
./scripts/dev/ssh-keys.sh all dev-01
./scripts/dev/ssh-keys.sh steady dev-01   # verify 通过后
```

详见 `docs/bootstrap/dev-ssh-keys.runbook.md`。

## WireGuard — Hub / Peer（`wireguard/`）

| 文件 | 是否提交 Git | 说明 |
|------|--------------|------|
| `wireguard/hub.private` | **否** | Hub WG 私钥 |
| `wireguard/hub.pub` | **是** | Hub WG 公钥 |
| `wireguard/<peer>.private` | **否** | Peer 私钥 |
| `wireguard/<peer>.pub` | **是** | Peer 公钥 |
| `../inventories/mgmt/group_vars/all/wireguard_vault.yml` | **是**（vault 加密） | Hub 私钥密文 |

```bash
chmod +x scripts/wireguard/wg-keys.sh
./scripts/wireguard/wg-keys.sh all-hub
./scripts/wireguard/wg-keys.sh vault-encrypt-hub
```

详见 `wireguard/README.md` 与 `docs/wireguard/wg-keys.runbook.md`。

---

改 Ansible 后 push 前请 `make ci`（见 `docs/contributing.md`）。
