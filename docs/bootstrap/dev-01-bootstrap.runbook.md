# Dev-01 Bootstrap Runbook（1.2）

> 主机：dev-01 | 公网 121.41.58.20 | 私网 172.21.226.38
> 前置：1.1 安全组已完成（bootstrap_status >= sg_done）

## Step 0 — 前置检查

### 0a. 静态质量（改 Ansible 后、实机 apply 前）

若本次变更是通过 Playbook/Ansible 执行 Bootstrap（非纯手工），在 CI 机上：

- [ ] 首次：`make setup`（见 [贡献指南](../contributing.md)）
- [ ] `make ci` 通过（改 inventory 时另跑 `make inventory`）
- [ ] PR 已合并或本地分支与远程 **CI Gate** 一致

`make ci` 为只读静态检查，**不能**替代下方实机验收。

### 0b. 主机与安全组

- [ ] 能以 root SSH 登录（公司 IP 或 CI 机）
- [ ] `cat /etc/os-release` → Debian 12
- [ ] 安全组已限制 22 端口来源（无 0.0.0.0/0）
- [ ] RDS 白名单含 172.21.226.38

## Step 1 — 系统基线

- [ ] `apt update && apt upgrade -y`
- [ ] `timedatectl set-timezone Asia/Shanghai`
- [ ] `systemctl enable --now systemd-timesyncd`
- [ ] `timedatectl` 显示 NTP synchronized

## Step 2 — 用户与 sudo

- [ ] `useradd -m -s /bin/bash deploy`
- [ ] `usermod -aG docker deploy`（docker 组在 Step 4 后生效）
- [ ] `useradd -r -s /usr/sbin/nologin jump_ops`
- [ ] 创建 `/etc/sudoers.d/deploy`：
      deploy ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker compose, /usr/bin/systemctl restart docker
- [ ] `visudo -c` 校验

## Step 3 — SSH 加固

- [ ] 创建 `/etc/ssh/sshd_config.d/99-dev-bootstrap.conf`：
      PermitRootLogin prohibit-password   # 1.3 完成后改 no
      PasswordAuthentication no
      PubkeyAuthentication yes
      AllowUsers deploy root              # 1.3 完成后去掉 root
- [ ] `sshd -t && systemctl reload sshd`
- [ ] **另开终端**验证 root/deploy 仍可密钥登录后再关旧会话

## Step 4 — Docker CE（官方源）

- [ ] 按 Docker 文档添加 bookworm apt repo
- [ ] 安装 docker-ce、docker-ce-cli、containerd.io、docker-compose-plugin
- [ ] `systemctl enable --now docker`
- [ ] `usermod -aG docker deploy`
- [ ] `docker run --rm hello-world` 成功

## Step 5 — 目录

- [ ] `mkdir -p /opt/app/compose /var/log/app`
- [ ] `chown -R deploy:deploy /opt/app /var/log/app`
- [ ] `chmod 750 /opt/app/compose`

## Step 6 — RAM 角色（控制台）

- [ ] 阿里云 ECS → dev-01 → 实例 RAM 角色 → 绑定 Dev-ECS-Role
- [ ] 实例内：`curl -s http://100.100.100.200/latest/meta-data/ram/security-credentials/` 可见角色名

## Step 7 — 主机防火墙

- [ ] `ufw disable`（若曾启用）
- [ ] 确认 ufw status → inactive
- [ ] **不**在主机上重复 1.1 安全组规则

## Step 8 — 回填台账

- [ ] `docs/assets/dev-01.yaml` → ram_role.attached: true
- [ ] `docs/assets/dev-01.yaml` → dependencies.rds.whitelist_ip: 172.21.226.38/32
- [ ] `bootstrap_status: bootstrap_done`
- [ ] Git commit

## Step 9 — 进入 1.3

- [ ] CI 机生成 ED25519 密钥对
- [ ] 公钥写入 deploy authorized_keys（或 `deploy_authorized_keys` 变量）
- [ ] 私钥入 GitHub Secret ANSIBLE_SSH_PRIVATE_KEY
- [ ] inventory `ansible_user` 改 deploy
- [ ] `ssh_allow_users` 去掉 root，`ssh_phase` 改 steady，`ssh_permit_root_login` 改 no