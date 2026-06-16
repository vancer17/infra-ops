# 阶段 F6：WireGuard 人员 Client 池 — Hub 登记与首台 Client 验收

> **控制机**：ci-01（yax / deploy）  
> **目标**：Hub wg0 登记五人笔记本 Peer（`10.200.10.1`–`.5`）  
> **验收日期**：2026-06-16  
> **原始日志**：`logs/console-acceptance.log`（F6 节）  
> **台账**：`docs/assets/wireguard-clients.yaml`

## 一、结论

| 范围 | 结论 |
|------|------|
| Hub 密钥生成 + inventory 同步 | **通过** |
| `wireguard-hub.yml` apply（6 Peer） | **通过** |
| ci-01 ↔ Hub 握手 | **通过** |
| `laptop-zhengyaoyuan` Client 握手 + 内网访问 | **通过** |
| billmiao / sammao / zhu / xinxin Client | **待完成**（Hub 已登记，无 handshake） |

## 二、人员名单与 Peer 映射

来源：`logs/remark.log`

| 人员 | Peer | WG IP | 角色 |
|------|------|-------|------|
| zhengyaoyuan | `laptop-zhengyaoyuan` | `10.200.10.1` | 开发/运维 |
| billmiao | `laptop-billmiao` | `10.200.10.2` | 开发 |
| sammao | `laptop-sammao` | `10.200.10.3` | 开发 |
| zhu | `laptop-zhu` | `10.200.10.4` | 开发 |
| xinxin | `laptop-xinxin` | `10.200.10.5` | 开发 |

## 三、Hub 验收（ci-01 → `deploy@10.200.0.1`）

```bash
ssh -i ansible/keys/infra-ci-deploy deploy@10.200.0.1 'sudo wg show wg0'
```

| # | 检查项 | 通过标准 | 结果 |
|---|--------|----------|------|
| 1 | Hub 监听 | `listening port: 51820` | OK |
| 2 | ci-01 Peer | `10.200.0.2/32`，handshake 近期 | OK |
| 3 | laptop-zhengyaoyuan | `10.200.10.1/32`，endpoint `125.121.146.255` | OK |
| 4 | laptop-billmiao | `10.200.10.2/32` 已登记 | OK（无 handshake） |
| 5 | laptop-sammao | `10.200.10.3/32` 已登记 | OK（无 handshake） |
| 6 | laptop-zhu | `10.200.10.4/32` 已登记 | OK（无 handshake） |
| 7 | laptop-xinxin | `10.200.10.5/32` 已登记 | OK（无 handshake） |
| 8 | Peer 总数 | 6（ci-01 + 5 笔记本） | OK |

公钥与 Hub `wg show` 对应关系见 `docs/assets/wireguard-clients.yaml` → `members[].public_key`。

## 四、运维笔记本 Client 验收（zhengyaoyuan / `develop`）

| # | 检查项 | 命令 / 标准 | 结果 |
|---|--------|-------------|------|
| 1 | Hub 握手 | `wg show` 见 `10.200.10.1` handshake | OK |
| 2 | JumpServer HTTPS | `curl -sk -o /dev/null -w '%{http_code}' https://jms.internal/` → `200` | OK |
| 3 | Hub 443 | `nc -zv 10.200.0.1 443` → open | OK |
| 4 | 内网 DNS | `ping -c 1 jms.internal` → `10.200.0.1` | OK |

## 五、已执行命令摘要

```bash
./scripts/wireguard/generate-team-laptop-peers.sh   # 四人密钥 + sync-inventory
git add ansible/keys/wireguard/laptop-*.pub ansible/inventories/mgmt/group_vars/all/wireguard.yml
ansible-playbook ansible/playbooks/wireguard-hub.yml -i ansible/inventories/mgmt/ --limit hub-01
```

## 六、待办（四人 Client）

```bash
# ci-01
for p in laptop-billmiao laptop-sammao laptop-zhu laptop-xinxin; do
  ./scripts/wireguard/render-laptop-conf.sh "$p" "/tmp/wg0-${p#laptop-}.conf"
done
# 经安全渠道分发；同事导入后复核：
ssh deploy@10.200.0.1 'sudo wg show wg0'   # 四人应出现 latest handshake
```

完成后将 `wireguard-clients.yaml` / `registry.yaml` 中对应成员 `status` 更新为 `operational`。

## 七、已更新台账

- `ansible/inventories/mgmt/group_vars/all/wireguard.yml` — 四人 `public_key` + `hub_peer_connected`
- `ansible/keys/wireguard/laptop-*.pub`
- `docs/assets/wireguard-clients.yaml`
- `docs/assets/registry.yaml` → `wireguard_plan.client_pool`
- `docs/assets/hub-01.yaml` → `stage_f6_wireguard_client_pool`

## 相关文档

- [wireguard-clients.yaml](../assets/wireguard-clients.yaml)
- [developer-laptop-client.md](../wireguard/developer-laptop-client.md)
- [办公笔记本 WG Client 接入指南](../wireguard/办公笔记本-WG-Client-接入指南.md)
