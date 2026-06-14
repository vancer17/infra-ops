# Dev-01 Bootstrap Runbook（1.2）

> **主机**：dev-01（与 ci-01 同 ECS「yax」）  
> **公网**：121.41.58.20 | **私网**：172.21.226.38  
> **前置**：1.1 安全组已完成；能以 `root` SSH 登录（阶段 A）

本 Runbook 以 **Ansible + `bootstrap.sh`** 为主路径（推荐）。文末「手工步骤对照」供排障时参考。

---

## 一、执行位置与环境

| 项 | 说明 |
|----|------|
| **在哪执行** | 在 **yax 本机**（`121.41.58.20`）上 clone 仓库并跑脚本；同机部署时脚本自动使用 `ansible_connection=local` |
| **执行用户** | 推荐 **`deploy`**（日常运维账号）；**不需要**控制机 sudo。Playbook 对远程 ECS 仍 `become: true`（root 装包/建用户） |
| **不要** | 在笔记本上对私网 `172.21.226.38` 跑 Ansible（除非改 inventory 为公网 IP） |
| **Python/Ansible** | 必须先 `make setup`；`bootstrap.sh` **不会**自动激活 `.venv` |

```bash
cd ~/infra-ops
make setup
source .venv/bin/activate    # 或：export PATH="$PWD/.venv/bin:$PATH"
```

未激活 venv 时 `preflight` 会报：`ERROR: ansible-playbook not found`。

---

## 二、Ansible 自动化流程（推荐）

### 2.1 静态检查（改仓库后、实机 apply 前）

```bash
make inventory    # 改了 inventories/dev/ 时
make ci
```

`make ci` 为只读检查，**不能**替代下方实机验收。

### 2.2 Bootstrap 命令

```bash
export ANSIBLE_INVENTORY=ansible/inventories/dev/
export ANSIBLE_LIMIT=dev-01    # 可省略，默认为 dev-01

chmod +x scripts/dev/bootstrap.sh

./scripts/dev/bootstrap.sh preflight
./scripts/dev/bootstrap.sh apply
./scripts/dev/bootstrap.sh verify

# 或一步：
./scripts/dev/bootstrap.sh all dev-01
```

**同机部署（ci-01 与 dev-01 同 ECS）**：

- 脚本检测到本机 IP 与 inventory 中 `ansible_host` 一致时，**自动**追加 `ansible_connection=local`。
- **不要**手写：`./scripts/dev/bootstrap.sh apply -e ansible_connection=local`  
  旧版脚本会把 `-e` 误当成主机名，导致 `ansible-playbook: error: argument -l/--limit: expected one argument`。

指定主机时请把**主机名放在子命令后、任何 `-` 选项前**：

```bash
# 正确
./scripts/dev/bootstrap.sh apply dev-01

# 错误（勿用）
./scripts/dev/bootstrap.sh apply -e ansible_connection=local
```

### 2.3 Playbook 执行顺序与 `import_role`

`ansible/playbooks/bootstrap.yml` 使用 `tasks` + `import_role` 按顺序导入（**勿**在 `roles:` 中重复同名 `common`）：

1. `import_role: common, tasks_from: base` — 时区、基础包、关 ufw  
2. `import_role: docker` — 安装 Docker、创建 `docker` 组  
3. `import_role: common, tasks_from: users` — `jump_ops`、`deploy`、sudo、SSH、目录  

若在 `roles:` 中两次引用 `common`，Ansible 2.16 可能两次都展开为 base（`allow_duplicates` 亦不可靠），表现为：

- `apply` 显示 `failed=0`，但无 `Create jump_ops user` 等任务  
- `id jump_ops` 不存在，`/opt/app/compose` 未创建  

预检：`ansible-playbook ... --list-tasks | grep jump_ops` 应能看到 users 任务。修复后重新 `apply`。

### 2.4 幂等验收

```bash
./scripts/dev/bootstrap.sh apply dev-01
```

第二次应 `changed=0`（或极少变更）。

### 2.5 实机验收清单

| # | 检查 | 命令 / 标准 |
|---|------|-------------|
| 1 | 时区 | `timedatectl \| grep 'Time zone: Asia/Shanghai'` |
| 2 | deploy 用户 | `id deploy`（应含 `docker` 组） |
| 3 | jump_ops | `id jump_ops` |
| 4 | 目录 | `test -d /opt/app/compose && echo OK` |
| 5 | Docker | `docker run --rm hello-world`（需等待镜像拉取完成） |
| 6 | RDS | `nc -z -w 5 rm-bp1wjjf373l7t331vno.mysql.rds.aliyuncs.com 3306`（须 `rds_verify: true`，见 `bootstrap.yml`） |
| 7 | ufw | `ufw status` → inactive（若已安装） |

也可：`./scripts/dev/bootstrap.sh verify dev-01`（同机时在本地执行检查；RDS 探测由 `rds_verify` + `network.yml` 的 `rds.host` 控制）。

### 2.6 回填台账

- [ ] `docs/assets/dev-01.yaml` → `bootstrap_status: bootstrap_done`（或 `sg_done` 后 `bootstrap_done`）
- [ ] `docs/assets/ci-01.yaml`、`docs/assets/registry.yaml` 与实机一致
- [ ] RAM 角色已在控制台绑定（若使用 OSS 验收，见 playbook `ram_role_verify`）

### 2.7 进入 1.3

见 [dev-ssh-keys.runbook.md](dev-ssh-keys.runbook.md)。

---

## 三、常见问题

### `ERROR: ansible-playbook not found`

未 `make setup` 或未 `source .venv/bin/activate`。见本文「一、执行位置与环境」。

### `argument -l/--limit: expected one argument`

把 `-e` 当成了 `LIMIT`。不要传 `-e ansible_connection=local`；使用 `./scripts/dev/bootstrap.sh apply` 或 `apply dev-01`。

### `apply OK` 但无 jump_ops / 无 `/opt/app/compose`

`common/users` 未执行。确认 `bootstrap.yml` 使用 `import_role` 导入 users，然后重新 `apply`（可用 `--list-tasks | grep jump_ops` 预检）。

### `WARN: complete step 1.1 (sg_done) before bootstrap`

资产台账 `bootstrap_status` 格式与脚本 grep 不一致时的提示；阶段 A 已完成可暂时忽略，或把台账写成 `bootstrap_status: "bootstrap_done"`。

### `community.general does not support Ansible version 2.16.18`

兼容性警告，可暂时忽略。

### verify 报 `nc: getaddrinfo for host "VARIABLE"`

mgmt（Hub）inventory 未定义 `rds.host` 且 `rds_verify` 未设为 `false` 时，旧版脚本会把 Ansible 的 `VARIABLE IS NOT DEFINED!` 当成主机名。Hub 须在 `mgmt/group_vars/all/bootstrap.yml` 设 `rds_verify: false`；Dev 保持 `rds_verify: true` 并确保 `network.yml` 含 `rds.host`。

### verify 报 `nc: getaddrinfo for host "false"`

remote verify 经 SSH 传参时，空字符串 positional argument 会被丢弃；若 `rds_host` 为空而 `docker_install=false` 排在第二位，远程 shell 会把 `false` 当成 `$1`（rds_host）并执行 `nc`。修复后 `docker_install` 在前、`rds_host` 在后；Hub 仍须 `rds_verify: false`。

### `sudo: a password is required`（`Stat CI deploy public key file on controller`）

Playbook 全局 `become: true`，但 `users.yml` / `ssh-keys.yml` 在控制机读 `ansible/keys/infra-ci-deploy.pub` 的 task 使用 `delegate_to: localhost`，须显式 **`become: false`**。以 `deploy` 跑 Ansible 时控制机不应 sudo。确认仓库已含该修复后重新 `apply`。

---

## 四、手工步骤对照（排障参考）

以下为 Ansible role 等价的手工检查项；**正常路径请用第二节**，不必逐步手工执行。

<details>
<summary>展开手工步骤清单</summary>

### Step 1 — 系统基线

- [ ] `apt update && apt upgrade -y`
- [ ] `timedatectl set-timezone Asia/Shanghai`
- [ ] `systemctl enable --now systemd-timesyncd`

### Step 2 — 用户与 sudo

- [ ] `useradd -m -s /bin/bash deploy`
- [ ] `usermod -aG docker deploy`
- [ ] `useradd -r -s /usr/sbin/nologin jump_ops`
- [ ] `/etc/sudoers.d/deploy`（docker 相关 NOPASSWD）

### Step 3 — SSH 加固

- [ ] `/etc/ssh/sshd_config.d/99-dev-bootstrap.conf`（见 role 模板）

### Step 4 — Docker CE

- [ ] 官方 apt 源安装 docker-ce、compose 插件
- [ ] `docker run --rm hello-world`

### Step 5 — 目录

- [ ] `/opt/app/compose`、`/var/log/app`，属主 `deploy`

### Step 6 — RAM 角色（控制台）

- [ ] 绑定 Dev-ECS-Role

### Step 7 — 主机防火墙

- [ ] `ufw disable`；以云安全组为主

</details>

---

## 五、相关文档

- [贡献指南](../contributing.md) — 三层检查、`make ci` 与实机分工
- [dev-ssh-keys.runbook.md](dev-ssh-keys.runbook.md) — 阶段 1.3
- [hub-01-bootstrap.runbook.md](hub-01-bootstrap.runbook.md) — Hub Bootstrap（阶段 C）
- [../plan/20260608-开发环境（Dev）部署计划.md](../plan/20260608-开发环境（Dev）部署计划.md)
