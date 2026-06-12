# Dev-01 Bootstrap 安全组 Runbook

> 主机：dev-01 | 公网：121.41.58.20 | 阶段：bootstrap
> 前置：Dev-01 已重装 Debian 12，可临时 root SSH（系统镜像默认或重置时保留的入口）

## Step 0 — 采集信息（写入 docs/assets/dev-01.yaml）

- [ ] ECS 控制台 → 实例详情 → 记录：实例 ID、地域、VPC、私网 IP、当前安全组
- [ ] 确认 CI 机 47.98.161.33 的私网 IP（若同 VPC）
- [ ] 确认公司出口公网 IP（`curl -4 ifconfig.me` 从办公网执行）
- [ ] 确认应用默认端口（8080 / 3000 / 其他）

## Step 1 — 创建安全组 sg-dev-ecs-bootstrap

路径：ECS → 网络与安全 → 安全组 → 创建安全组

- [ ] 名称：`sg-dev-ecs-bootstrap`
- [ ] 网络类型：与 Dev-01 相同 VPC
- [ ] 描述：`Dev ECS Bootstrap 临时策略`
- [ ] **不**添加任何「快速规则/全部放行」模板
- [ ] 记录安全组 ID → 回填 `docs/assets/dev-01.yaml`

## Step 2 — 添加入站规则（严格按 dev-ecs-bootstrap.rules.yaml）

路径：安全组 → sg-dev-ecs-bootstrap → 入方向 → 手动添加

按优先级依次添加：

- [ ] TCP 22 ← 47.98.161.33/32 （CI-SSH）
- [ ] TCP 22 ← <公司出口>/32 （Office-SSH）
- [ ] TCP 80 ← <公司出口>/32 （可选，Nginx 前期）
- [ ] TCP 443 ← <公司出口>/32 （可选）
- [ ] TCP 8080 ← <公司出口>/32 （应用联调，端口按实际）
- [ ] （可选）TCP 22 ← <CI 私网 IP>/32
- [ ] 确认**无** 0.0.0.0/0 入站规则

## Step 3 — 添加出站规则

- [ ] 出方向：全部协议，目的 0.0.0.0/0，策略：允许
- [ ] 若已有默认「全部允许」出站，保持不变即可

## Step 4 — 绑定 Dev-01

路径：ECS → 实例 dev-01 → 安全组 → 修改

- [ ] **替换**默认安全组，仅保留 `sg-dev-ecs-bootstrap`
- [ ] 若需零 downtime 验证：先「添加」新组，验证通过后再「移除」旧组
- [ ] 截图或导出规则列表存档（可选附件）

## Step 5 — RDS 白名单（同步动作）

路径：RDS → 数据安全性 → 白名单设置

- [ ] 新建/modify 分组 `dev-ecs`
- [ ] 添加 Dev-01 私网 IP（**不要**加 121.41.58.20 公网 IP）
- [ ] Dev-02 私网 IP 标记 pending，待 Dev-02 重置后补

## Step 6 — 验证（见下方验收清单）

- [ ] 更新 `docs/assets/dev-01.yaml` → `bootstrap_status: sg_done`
- [ ] Git commit：`chore(security): bootstrap SG for dev-01`

## Step 7 — 清理（若从旧环境迁移）

- [ ] 删除 Dev-01 上旧安全组绑定（含「全部开放」组）
- [ ] 确认无遗留 EIP 指向错误实例
- [ ] 确认无宝塔/8888 等历史端口规则