# 人员笔记本 WireGuard Client（运维简版）

> **同事接入**：请阅读并分发 **[办公笔记本 WG Client 接入指南](./办公笔记本-WG-Client-接入指南.md)**。
>
> 本文档供 infra 维护 inventory、Hub Peer 与密钥时快速查阅。

## 团队台账（2026-06-16 验收）

SSOT：`docs/assets/wireguard-clients.yaml`  
验收报告：[阶段 F6 WireGuard 人员 Client 池](../acceptance/20260616-阶段F6-WireGuard人员Client池验收.md)

| Peer | 人员 | WG 地址 | 角色 | 状态 |
|------|------|---------|------|------|
| `laptop-zhengyaoyuan` | zhengyaoyuan | `10.200.10.1` | 开发/运维 | **operational** |
| `laptop-billmiao` | billmiao | `10.200.10.2` | 开发 | hub_registered（待 Client） |
| `laptop-sammao` | sammao | `10.200.10.3` | 开发 | hub_registered（待 Client） |
| `laptop-zhu` | zhu | `10.200.10.4` | 开发 | hub_registered（待 Client） |
| `laptop-xinxin` | xinxin | `10.200.10.5` | 开发 | hub_registered（待 Client） |

开发角色 Client AllowedIPs：`10.200.0.0/24, 10.200.1.0/24, 10.200.2.0/24`（不含 Prod）。

## 当前状态（2026-06-16）

- Hub Server 与 ci-01：**operational**
- Hub `wg0`：**6 Peer** 已登记（ci-01 + 五人笔记本）
- `laptop-zhengyaoyuan`：握手 OK；`jms.internal` HTTPS 200、DNS/ping 正常
- 四人：Hub 已登记公钥，**待** `render-laptop-conf.sh` 分发 `wg0.conf` 与 Client 握手

## 待办：四人 Client 接入

```bash
cd ~/infra-ops

for p in laptop-billmiao laptop-sammao laptop-zhu laptop-xinxin; do
  ./scripts/wireguard/render-laptop-conf.sh "$p" "/tmp/wg0-${p#laptop-}.conf"
done

# 验收（同事导入配置并激活后）
ssh deploy@10.200.0.1 'sudo wg show wg0'
```

## 配置模板

- 运维：`ansible/keys/wireguard/laptop-zhengyaoyuan.conf.example`
- 开发：`ansible/keys/wireguard/laptop-client-dev.conf.example`

## 安全说明

- 每人独立密钥，禁止共用旧 `developer-laptop` 私钥
- 不要将 `*.private` 或含私钥的 `wg0.conf` 提交 Git
- 笔记本丢失：Hub 移除 Peer 公钥并 `wireguard-hub.yml` 再 apply

## 相关文档

- [办公笔记本-WG-Client-接入指南.md](./办公笔记本-WG-Client-接入指南.md)
- [Clash Verge 与 WG/SSH 共存指南](./clash-verge-wg-ssh-bypass.md)（分发 WG 时，若对方使用跨境代理一并发送）
- [wireguard-clients.yaml](../assets/wireguard-clients.yaml)
- [stage-f-console-checklist.md](./stage-f-console-checklist.md)
