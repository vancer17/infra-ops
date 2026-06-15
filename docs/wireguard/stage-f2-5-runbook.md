# 阶段 F2-5：WireGuard 收口与后续步骤

F2 握手完成（`wireguard.status: operational`）且 F2-4 台账已更新后执行。

## 范围

| 步骤 | 本期做 | 说明 |
|------|--------|------|
| `access_mode: wireguard` | 是 | Hub `ansible_host` → `10.200.0.1` |
| `network_phase: wireguard` | 是 | 与 registry 对齐 |
| GitHub Self-hosted Runner | 可选 | `register-github-runner.sh` |
| 运维笔记本 Peer | 可选 | `developer-laptop-client.md` |
| 关公网 SSH | **否** | `network_phase: steady` |
| Hub 独立安全组 | **否** | 二期 |

## 在 ci-01 上执行

```bash
cd ~/infra-ops
git pull   # 含 F2-5 inventory 变更

export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy

chmod +x scripts/mgmt/stage-f2-5-followup.sh
make stage-f2-5-followup
```

## 注册 Runner（可选）

1. GitHub → 仓库 **Settings → Actions → Runners → New self-hosted runner**
2. 复制 **Registration token**（一次性）
3. 在 ci-01：

```bash
export RUNNER_REGISTRATION_TOKEN="粘贴 token"
./scripts/mgmt/register-github-runner.sh
```

4. 更新 `docs/assets/ci-01.yaml` → `github_runner.status: registered`

## 运维笔记本（可选）

见 [developer-laptop-client.md](developer-laptop-client.md)。

## 验收

| # | 项 | 标准 |
|---|-----|------|
| 1 | `stage-f2-5-followup.sh` | 全绿 |
| 2 | `hub-01 ansible_host` | `10.200.0.1` |
| 3 | `ansible ping hub-01` | success |
| 4 | Runner（若注册） | GitHub 显示 Idle |
