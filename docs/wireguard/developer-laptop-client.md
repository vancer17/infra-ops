# 运维笔记本 WireGuard Client

Hub 已登记 `developer-laptop` Peer（`10.200.10.1/32`）。私钥**仅保留在笔记本**，公钥已在 Git：`ansible/keys/wireguard/developer-laptop.pub`。

## 参数（与 inventory 一致）

| 项 | 值 |
|----|-----|
| 本机 WG 地址 | `10.200.10.1/32` |
| Hub Endpoint | `121.43.49.58:51820` |
| Hub 公钥 | 见 `ansible/keys/wireguard/hub.pub` 或 `wireguard.hub_public_key` |
| AllowedIPs | `10.200.0.0/24`, `10.200.1.0/24`（开发用，不含 Prod `10.200.3.0/24`） |
| PersistentKeepalive | `25` |

## Linux / macOS（wireguard-tools）

1. 在笔记本生成密钥（若尚未生成）：

```bash
wg genkey | tee developer-laptop.private | wg pubkey > developer-laptop.pub
chmod 600 developer-laptop.private
```

若公钥与仓库不一致，在 ci-01 更新 Peer 并重新 apply Hub Server。

2. 复制模板并填入私钥：

```bash
cp ansible/keys/wireguard/developer-laptop.conf.example /etc/wireguard/wg0.conf
# 编辑 PrivateKey 行
sudo chmod 600 /etc/wireguard/wg0.conf
sudo wg-quick up wg0
```

3. 验收：

```bash
sudo wg show
ping -c 3 10.200.0.1
ping -c 3 10.200.0.2
ssh -i /path/to/infra-ci-deploy deploy@10.200.0.1
```

## Windows

使用 [WireGuard 官方客户端](https://www.wireguard.com/install/)，导入与 `developer-laptop.conf.example` 等价的配置。

## 安全说明

- 不要将 `*.private` 提交 Git
- 笔记本丢失时：在 Hub 上移除该 Peer 公钥并轮换
