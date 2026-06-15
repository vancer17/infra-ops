# 阶段 F3：验收与台账收口

F1（Hub Server）、F2（ci-01 Client 握手）、F2-5（Ansible 经 WG）完成后执行。

完整报告：[20260614-阶段F-WireGuard验收报告.md](../acceptance/20260614-阶段F-WireGuard验收报告.md)

---

## F3-1 自动化检查（ci-01）

```bash
cd ~/infra-ops
export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy

make stage-f-preflight
./scripts/wireguard/wg-keys.sh verify-hub
./scripts/wireguard/wg-keys.sh verify-peer ci-01
make inventory-mgmt
make secret-scan
```

### 通过标准

| 输出 | 含义 |
|------|------|
| `hub-01: access_mode=wireguard ansible_host=10.200.0.1 OK` | Ansible 主路径已切 WG |
| `wireguard.enabled=true status=operational` | 配置与实机一致 |
| `wireguard-hub.yml` / `wireguard-peer.yml` `--list-hosts OK` | Playbook 目标正确 |
| `ci-01: connection=local limited_sudo=true OK` | 本机 Peer 可管理 |
| `[stage-f-preflight] OK` | 预检脚本全通过 |
| `gitleaks ... no leaks found` | 仓库无密钥泄漏 |

### 可选实机复核

```bash
sudo wg show wg0
ping -c 3 10.200.0.1
ssh -i ~/infra-ops/ansible/keys/infra-ci-deploy deploy@10.200.0.1 'sudo wg show | head -20'
```

---

## F3-2 台账确认（文档）

确认以下文件已反映 `operational`（本仓库 `docs/assets/` 与 `registry.yaml`）：

- [hub-01.yaml](../assets/hub-01.yaml) — `wireguard_status`、`wireguard_server`、`stage_f3_acceptance`
- [ci-01.yaml](../assets/ci-01.yaml) — `wireguard_client`、`stage_f3_acceptance`
- [registry.yaml](../assets/registry.yaml) — `network_phase: wireguard`、`stage_f3_acceptance`

---

## F3-3 可选后续（非阻塞）

| 项 | 入口 |
|----|------|
| GitHub Runner | `scripts/mgmt/register-github-runner.sh` |
| 笔记本 WG | [developer-laptop-client.md](developer-laptop-client.md) |
| UDP 控制台核对 | [stage-f-console-checklist.md](stage-f-console-checklist.md) |
| 关公网 SSH / steady | 企业方案 §网络收口（未开始） |

---

## 验收日志归档

| 日志 | 内容 |
|------|------|
| `logs/console-acceptance.log` | F2 实机 + F3-1 自动化 |
| `logs/console-check.log` | F2-5 收口 |
