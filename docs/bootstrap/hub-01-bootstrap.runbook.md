# Hub-01 Bootstrap Runbook（1.2）

> **主机**：hub-01（`launch-advisor-20241121`）  
> **公网**：121.43.49.58 | **私网**：172.21.127.123  
> **前置**：dev-01/ci-01（yax）已完成 Bootstrap，可作为 Ansible 控制机

Hub 使用 **`inventories/mgmt/`**，**不安装 Docker**（见 `group_vars/all/bootstrap.yml`）。

---

## 一、在控制机（yax）上执行

```bash
cd ~/infra-ops
source .venv/bin/activate

export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
export ANSIBLE_LIMIT=hub-01

make inventory-mgmt

./scripts/dev/bootstrap.sh preflight hub-01
./scripts/dev/bootstrap.sh apply hub-01
./scripts/dev/bootstrap.sh verify hub-01

# 或：
./scripts/dev/bootstrap.sh all hub-01
```

控制机与 Hub **不同机**，脚本走 **SSH**（`root@172.21.127.123` 或公网，以 inventory 解析为准），**不要**加 `-e ansible_connection=local`。

---

## 二、验收清单

| # | 检查 | 说明 |
|---|------|------|
| 1 | 时区 | `Asia/Shanghai` |
| 2 | deploy 用户 | `id deploy`（Hub 无 docker 组） |
| 3 | jump_ops | `id jump_ops` |
| 4 | 目录 | `test -d /opt/mgmt && test -d /opt/wireguard` |
| 5 | Docker | **不应**安装（`docker` 命令可不存在） |
| 6 | 幂等 | 第二次 `apply` → `changed=0` |

---

## 三、SSH 密钥（1.3）

```bash
export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
./scripts/dev/ssh-keys.sh all hub-01
./scripts/dev/ssh-keys.sh steady hub-01
```

---

## 四、台账

- [ ] `docs/assets/hub-01.yaml` → `bootstrap_status` 更新
- [ ] `docs/assets/registry.yaml` 与实机一致

---

## 五、下一步

- WireGuard 密钥：[wg-keys.runbook.md](../wireguard/wg-keys.runbook.md)
- 后续：`wireguard-hub.yml`（待实现）

## 六、相关文档

- [dev-01-bootstrap.runbook.md](dev-01-bootstrap.runbook.md)
- [ansible/inventories/mgmt/README.md](../../ansible/inventories/mgmt/README.md)
