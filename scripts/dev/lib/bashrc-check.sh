#!/usr/bin/env bash
# =============================================================================
# scripts/dev/lib/bashrc-check.sh — ~/.bashrc 控制面配置检查
# =============================================================================
#
# 【用途】
#   判断 bashrc 中是否仍含有指向 hub-root 的 ANSIBLE_PRIVATE_KEY_FILE 赋值。
#   忽略以 # 开头的注释行，避免误报（例如 control-plane 块内的说明注释）。
#
# 【用法】
#   source scripts/dev/lib/bashrc-check.sh
#   if bashrc_has_stale_ansible_hub_root; then echo "still stale"; fi
#
# 【返回值】
#   bashrc_has_stale_ansible_hub_root [file]
#     0 — 发现有效（非注释）残留赋值，应清理
#     1 — 未发现残留，或文件不存在
#
# =============================================================================

if [[ -n "${BASHRC_CHECK_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
BASHRC_CHECK_LOADED=1

# 检测 bashrc 中是否存在指向 hub-root 的有效 ANSIBLE_PRIVATE_KEY_FILE 赋值（非注释行）
bashrc_has_stale_ansible_hub_root() {
  local bashrc="${1:-${HOME}/.bashrc}"

  [[ -f "$bashrc" ]] || return 1

  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /ANSIBLE_PRIVATE_KEY_FILE/ && /hub-root/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$bashrc"
}

# 删除 bashrc 中指向 hub-root 的有效赋值行（保留注释）
bashrc_remove_stale_ansible_hub_root() {
  local bashrc="${1:-${HOME}/.bashrc}"

  [[ -f "$bashrc" ]] || return 0

  sed -i '/^[[:space:]]*#/!{/ANSIBLE_PRIVATE_KEY_FILE.*hub-root/d;}' "$bashrc"
  sed -i '/^[[:space:]]*#.*Hub Bootstrap：Ansible 连 Hub 的 root 密钥/d' "$bashrc"
}
