#!/usr/bin/env bash
# =============================================================================
# ci-01 deploy 受限 sudo（deploy-wireguard）检测 / 控制台指引（阶段 F2 前置）
# =============================================================================
#
# 【背景】
#   wireguard-peer.yml 在 ci-01 本机以 deploy 运行，经 sudo -n tee/systemctl 写 wg0.conf。
#   Bootstrap 仅配置 sudo_docker；WireGuard 需单独 /etc/sudoers.d/deploy-wireguard。
#
# 【用法】
#   ./scripts/mgmt/apply-ci-wireguard-sudo.sh              # 检测 deploy 受限 sudo
#   ./scripts/mgmt/apply-ci-wireguard-sudo.sh --console    # 打印 root 一次性命令
#
# 【执行位置】
#   ci-01（yax）上以 deploy 用户运行（或 root 直接应用 --console 输出）
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUDOERS_SRC="${ROOT}/ansible/roles/wireguard/files/deploy-wireguard.sudoers"
SUDOERS_DEST="/etc/sudoers.d/deploy-wireguard"

CONSOLE_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --console    输出 root 在 ci-01 工作台执行的一次性命令（不检测）
  -h, --help   显示帮助

After deploy has deploy-wireguard sudo:
  ansible-playbook ansible/playbooks/wireguard-peer.yml \\
    -i ansible/inventories/mgmt/ --limit ci-01 \\
    --vault-password-file .vault_pass --check --diff
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --console) CONSOLE_ONLY=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -f "${SUDOERS_SRC}" ]] || {
  echo "ERROR: missing sudoers template: ${SUDOERS_SRC}" >&2
  exit 1
}

print_console_instructions() {
  cat <<EOF

================================================================================
ci-01 deploy 尚无 deploy-wireguard 受限 sudo — 请用 root（工作台）执行一次：
================================================================================

tee ${SUDOERS_DEST} > /dev/null <<'SUDOERS_EOF'
$(sed '/^# Source:/d' "${SUDOERS_SRC}")
SUDOERS_EOF
chmod 440 ${SUDOERS_DEST}
visudo -cf ${SUDOERS_DEST} && echo "OK: deploy-wireguard sudoers"

然后切回 deploy 验证：

  sudo -n wg show
  sudo -n install -d -m 700 /etc/wireguard
  echo test | sudo -n tee /etc/wireguard/wg0.conf > /dev/null && sudo -n wg show wg0

（tee 仅允许固定路径 wg0.conf；其它路径应拒绝）

成功后运行 wireguard-peer.yml：

  ansible-playbook ansible/playbooks/wireguard-peer.yml \\
    -i ansible/inventories/mgmt/ --limit ci-01 \\
    --vault-password-file .vault_pass --check --diff

================================================================================
EOF
}

check_deploy_wireguard_sudo() {
  local ok=true

  if ! sudo -n /usr/bin/wg show >/dev/null 2>&1; then
    echo "[apply-ci-wireguard-sudo] FAIL: sudo -n wg show" >&2
    ok=false
  fi

  if ! sudo -n /usr/bin/install -d -m 700 /etc/wireguard >/dev/null 2>&1; then
    echo "[apply-ci-wireguard-sudo] FAIL: sudo -n install -d -m 700 /etc/wireguard" >&2
    ok=false
  fi

  if ! sudo -n /bin/systemctl is-enabled wg-quick@wg0 >/dev/null 2>&1 \
    && ! sudo -n /bin/systemctl status wg-quick@wg0 >/dev/null 2>&1; then
    echo "[apply-ci-wireguard-sudo] FAIL: sudo -n systemctl (wg-quick@wg0)" >&2
    ok=false
  fi

  [[ "${ok}" == "true" ]]
}

if [[ "$CONSOLE_ONLY" == "true" ]]; then
  print_console_instructions
  exit 0
fi

echo "[apply-ci-wireguard-sudo] checking deploy@${HOSTNAME:-ci-01} limited sudo..."

if check_deploy_wireguard_sudo; then
  echo "[apply-ci-wireguard-sudo] OK — deploy-wireguard sudoers present"
  exit 0
fi

print_console_instructions
echo "[apply-ci-wireguard-sudo] After console fix, re-run: $(basename "$0")"
exit 1
