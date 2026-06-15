# JumpServer on Hub

Compose 由 Ansible `jumpserver` role 部署到 Hub `/opt/mgmt/jumpserver/`。

| 文件 | 说明 |
|------|------|
| `docker-compose.yml` | 仓库参考副本；CI `docker-validate` 校验 |
| Hub 实机 `.env` | 由 vault 渲染，权限 600，不进 Git |
| `.env.example` | CI `docker-validate` 占位符（非生产密钥） |

## 文档

- [hub-jumpserver.runbook.md](../docs/jumpserver/hub-jumpserver.runbook.md)
- [hub-docker.runbook.md](../docs/docker/hub-docker.runbook.md)

## 镜像

轩辕专属前缀（免交互鉴权）：

`5yrqsf19ms2mh4.xuanyuan.run/jumpserver/jms_all:<tag>`

变量见 `ansible/inventories/mgmt/group_vars/all/jumpserver.yml`。
