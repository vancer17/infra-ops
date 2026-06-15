#!/usr/bin/env bash
# =============================================================================
# scripts/ci/inventory-check-mgmt.sh — Mgmt Inventory 解析与连通性地址校验
# =============================================================================
#
# 【用途】
#   在修改 inventories/mgmt/ 后验证：
#     1. mgmt inventory 可被 ansible-inventory 正确解析
#     2. hub-01 的 ansible_host / ansible_user 经 Jinja2 展开后为预期值
#     3. CI 与 Hub 同 VPC 时 ansible_host 优先私网；跨 VPC 时禁止误用私网
#
# 【与 inventory-check.sh 的分工】
#   inventory-check.sh      → inventories/dev/
#   inventory-check-mgmt.sh → inventories/mgmt/（本脚本）
#
# 【用法】
#   ./scripts/ci/inventory-check-mgmt.sh
#   make inventory-mgmt   # 若含 wireguard_vault.yml，需 .vault_pass 或 ANSIBLE_VAULT_PASSWORD_FILE
#
# 【Vault】
#   mgmt/group_vars/all/wireguard_vault.yml 为加密文件；须设置
#   ANSIBLE_VAULT_PASSWORD_FILE 或仓库根目录 .vault_pass，否则 ansible 无法解析 inventory。
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd ansible-inventory
ci_require_cmd ansible

MGMT_INVENTORY="${CI_ANSIBLE_INVENTORY_MGMT}"

# 阶段 E 起 mgmt inventory 含 ansible-vault 加密 vars；自动使用 .vault_pass（若存在）
if [[ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" && -f "${CI_REPO_ROOT}/.vault_pass" ]]; then
  export ANSIBLE_VAULT_PASSWORD_FILE="${CI_REPO_ROOT}/.vault_pass"
fi
if [[ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]]; then
  ci_log "Ansible vault: ${ANSIBLE_VAULT_PASSWORD_FILE}"
fi

# -----------------------------------------------------------------------------
# resolved_host_var — 获取已渲染的 inventory 变量（与 dev 版脚本同源逻辑）
# -----------------------------------------------------------------------------
resolved_host_var() {
  local host_name="$1"
  local var_name="$2"

  ci_cd ansible "${host_name}" \
    -i "${MGMT_INVENTORY}" \
    -m ansible.builtin.debug \
    -a "var=${var_name}" \
    -c local \
    2>/dev/null | python3 -c "
import json, re, sys

host = '''${host_name}'''
var_name = '''${var_name}'''
text = sys.stdin.read()
match = re.search(r'=>\s*(\{.*\})\s*$', text, re.DOTALL)
if not match:
    sys.exit(1)
payload = json.loads(match.group(1))
val = payload.get(var_name, '')
if isinstance(val, bool):
    print(str(val).lower())
elif isinstance(val, (dict, list)):
    print(json.dumps(val))
elif val is None:
    print('')
else:
    print(val)
"
}

is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
  return 1
}

# -----------------------------------------------------------------------------
# check_ci_hub_connectivity — CI 到 Hub 的 ansible_host 策略门禁
# -----------------------------------------------------------------------------
check_ci_hub_connectivity() {
  local host_name="$1"
  local ansible_host="$2"
  local same_vpc
  local access_mode

  same_vpc="$(resolved_host_var "${host_name}" "ci_connectivity.same_vpc_as_ci")"
  same_vpc="${same_vpc:-false}"
  access_mode="$(resolved_host_var "${host_name}" "ci_connectivity.access_mode")"
  access_mode="${access_mode:-public}"

  if [[ "${access_mode}" == "wireguard" ]]; then
    if [[ ! "${ansible_host}" =~ ^10\.200\. ]]; then
      ci_die "host ${host_name}: access_mode=wireguard 但 ansible_host=${ansible_host} 非 10.200.x.x"
    fi
    ci_log "  ${host_name}: access_mode=wireguard ansible_host=${ansible_host} OK"
    return 0
  fi

  if [[ "${same_vpc}" == "false" ]] && is_private_ip "${ansible_host}"; then
    ci_die "host ${host_name}: CI 与 Hub 跨 VPC，ansible_host 不能使用私网: ${ansible_host}"
  fi

  if [[ "${same_vpc}" == "true" ]] && [[ "${ansible_host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! is_private_ip "${ansible_host}"; then
    ci_log "WARN: host ${host_name}: same_vpc_as_ci=true 但 ansible_host 为公网 ${ansible_host}，请确认是否应使用 Hub 私网"
  fi
}

ci_log "Mgmt inventory graph: ${MGMT_INVENTORY}"
ci_cd ansible-inventory -i "${MGMT_INVENTORY}" --graph

mapfile -t mgmt_hosts < <(
  ci_cd ansible mgmt -i "${MGMT_INVENTORY}" --list-hosts 2>/dev/null \
    | awk '/^[[:space:]]+hub-/ { print $1 }' \
    | sort -u
)

if [[ ${#mgmt_hosts[@]} -eq 0 ]]; then
  ci_die "no hosts found in mgmt group (check ansible/inventories/mgmt/hosts.yml)"
fi

ci_log "Checking ${#mgmt_hosts[@]} host(s) in mgmt group..."

for host_name in "${mgmt_hosts[@]}"; do
  ansible_host="$(resolved_host_var "${host_name}" "ansible_host")"
  ansible_user="$(resolved_host_var "${host_name}" "ansible_user")"
  planned_wg="$(resolved_host_var "${host_name}" "wireguard.hub_address")"

  [[ -n "${ansible_host}" ]] || ci_die "host ${host_name}: ansible_host is empty"
  [[ "${ansible_host}" != *"{{"* ]] || ci_die "host ${host_name}: ansible_host has unresolved Jinja2"

  ci_log "  ${host_name}: ansible_user=${ansible_user:-<unset>} ansible_host=${ansible_host} planned_wg=${planned_wg:-<unset>}"
  check_ci_hub_connectivity "${host_name}" "${ansible_host}"

  # steady 阶段门禁：inventory 须使用 deploy，避免仍指向 root（交叉检查黄灯 3）
  ssh_phase="$(resolved_host_var "${host_name}" "ssh_phase")"
  ssh_keys_configured="$(resolved_host_var "${host_name}" "ssh_keys_configured")"
  if [[ "${ssh_phase}" == "steady" ]]; then
    if [[ "${ansible_user}" != "deploy" ]]; then
      ci_die "host ${host_name}: ssh_phase=steady 但 ansible_user=${ansible_user:-<unset>}，应为 deploy（检查 group_vars/all/ssh.yml）"
    fi
    ci_log "  ${host_name}: ssh_phase=steady ssh_keys_configured=${ssh_keys_configured:-<unset>} OK"
  fi

  wireguard_enabled="$(resolved_host_var "${host_name}" "wireguard.enabled")"
  wg_status="$(resolved_host_var "${host_name}" "wireguard.status")"
  ci_log "  ${host_name}: wireguard.enabled=${wireguard_enabled:-<unset>} status=${wg_status:-<unset>}"

  if [[ "${wg_status}" == "keys_ready" || "${wg_status}" == "server_up" || "${wg_status}" == "operational" ]]; then
    hub_pub="$(resolved_host_var "${host_name}" "wireguard.hub_public_key")"
    if [[ -z "${hub_pub}" || "${hub_pub}" == "null" ]]; then
      ci_die "host ${host_name}: wireguard.status=${wg_status} 但 hub_public_key 为空"
    fi
    ci_log "  ${host_name}: wireguard ${wg_status} hub_public_key present OK"
  fi

  if [[ "${wg_status}" == "server_up" || "${wg_status}" == "operational" ]]; then
    if [[ "${wireguard_enabled}" != "true" ]]; then
      ci_die "host ${host_name}: wireguard.status=${wg_status} 但 wireguard.enabled 不为 true"
    fi
    ci_log "  ${host_name}: wireguard.enabled=true OK (Hub Server 已登记)"
  fi

  nginx_enabled="$(resolved_host_var "${host_name}" "nginx.enabled")"
  nginx_status="$(resolved_host_var "${host_name}" "nginx.status")"
  nginx_gateway="$(resolved_host_var "${host_name}" "nginx_gateway")"
  ci_log "  ${host_name}: nginx.enabled=${nginx_enabled:-<unset>} status=${nginx_status:-<unset>}"

  if [[ "${nginx_status}" == "operational" ]]; then
    if [[ "${nginx_enabled}" != "true" ]]; then
      ci_die "host ${host_name}: nginx.status=operational 但 nginx.enabled 不为 true"
    fi
    if [[ "${nginx_gateway}" != "true" ]]; then
      ci_die "host ${host_name}: nginx.status=operational 但 nginx_gateway 不为 true"
    fi
    ci_log "  ${host_name}: nginx operational OK (Hub gateway 已登记)"
  fi
done

# -----------------------------------------------------------------------------
# bootstrap playbook 目标组门禁 — hub-01 须被 dev:mgmt union 选中
# -----------------------------------------------------------------------------
bootstrap_playbook="${CI_REPO_ROOT}/ansible/playbooks/bootstrap.yml"
if [[ -f "${bootstrap_playbook}" ]]; then
  list_out="$(ci_cd ansible-playbook "${bootstrap_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --limit hub-01 \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'hub-01' <<<"${list_out}"; then
    ci_log "bootstrap.yml --list-hosts OK for hub-01 (mgmt inventory)"
  else
    ci_die "bootstrap.yml does not target hub-01 with mgmt inventory; check hosts: dev:mgmt"
  fi
fi

wireguard_hub_playbook="${CI_REPO_ROOT}/ansible/playbooks/wireguard-hub.yml"
if [[ -f "${wireguard_hub_playbook}" ]]; then
  wg_list_out="$(ci_cd ansible-playbook "${wireguard_hub_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --limit hub-01 \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'hub-01' <<<"${wg_list_out}"; then
    ci_log "wireguard-hub.yml --list-hosts OK for hub-01 (mgmt inventory)"
  else
    ci_die "wireguard-hub.yml does not target hub-01; check hosts: mgmt_hub"
  fi
fi

wireguard_peer_playbook="${CI_REPO_ROOT}/ansible/playbooks/wireguard-peer.yml"
if [[ -f "${wireguard_peer_playbook}" ]]; then
  wg_peer_list_out="$(ci_cd ansible-playbook "${wireguard_peer_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --limit ci-01 \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'ci-01' <<<"${wg_peer_list_out}"; then
    ci_log "wireguard-peer.yml --list-hosts OK for ci-01 (mgmt inventory)"
  else
    ci_die "wireguard-peer.yml does not target ci-01; check hosts: wireguard_peers"
  fi
fi

nginx_hub_playbook="${CI_REPO_ROOT}/ansible/playbooks/nginx-hub.yml"
if [[ -f "${nginx_hub_playbook}" ]]; then
  ngx_list_out="$(ci_cd ansible-playbook "${nginx_hub_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'hub-01' <<<"${ngx_list_out}"; then
    ci_log "nginx-hub.yml --list-hosts OK for hub-01 (mgmt inventory)"
  else
    ci_die "nginx-hub.yml does not target hub-01; check hosts: mgmt_hub"
  fi
fi

hub_g2_playbook="${CI_REPO_ROOT}/ansible/playbooks/hub-g2.yml"
if [[ -f "${hub_g2_playbook}" ]]; then
  g2_list_out="$(ci_cd ansible-playbook "${hub_g2_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'hub-01' <<<"${g2_list_out}"; then
    ci_log "hub-g2.yml --list-hosts OK for hub-01 (mgmt inventory)"
  else
    ci_die "hub-g2.yml does not target hub-01; check hosts: mgmt_hub"
  fi
fi

hub_g3_docker_playbook="${CI_REPO_ROOT}/ansible/playbooks/hub-g3-docker.yml"
if [[ -f "${hub_g3_docker_playbook}" ]]; then
  g3_list_out="$(ci_cd ansible-playbook "${hub_g3_docker_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'hub-01' <<<"${g3_list_out}"; then
    ci_log "hub-g3-docker.yml --list-hosts OK for hub-01 (mgmt inventory)"
  else
    ci_die "hub-g3-docker.yml does not target hub-01; check hosts: mgmt_hub"
  fi
fi

hub_g4_jumpserver_playbook="${CI_REPO_ROOT}/ansible/playbooks/hub-g4-jumpserver.yml"
jumpserver_vault_file="${CI_REPO_ROOT}/ansible/inventories/mgmt/group_vars/all/jumpserver_vault.yml"
if [[ -f "${hub_g4_jumpserver_playbook}" ]] && [[ ! -f "${jumpserver_vault_file}" ]]; then
  ci_log "WARN: jumpserver_vault.yml missing; run ./scripts/mgmt/jumpserver-vault-init.sh before G4 apply"
fi
if [[ -f "${hub_g4_jumpserver_playbook}" ]]; then
  g4_list_out="$(ci_cd ansible-playbook "${hub_g4_jumpserver_playbook}" \
    -i "${MGMT_INVENTORY}" \
    --limit hub-01 \
    --list-hosts 2>/dev/null || true)"
  if grep -q 'hub-01' <<<"${g4_list_out}"; then
    ci_log "hub-g4-jumpserver.yml --list-hosts OK for hub-01 (mgmt inventory)"
  else
    ci_die "hub-g4-jumpserver.yml does not target hub-01; check hosts: mgmt_hub"
  fi
fi

# -----------------------------------------------------------------------------
# internal_dns — G2 门禁（operational 后校验）
# -----------------------------------------------------------------------------
for host_name in "${mgmt_hosts[@]}"; do
  internal_dns_enabled="$(resolved_host_var "${host_name}" "internal_dns.enabled")"
  internal_dns_status="$(resolved_host_var "${host_name}" "internal_dns.status")"
  dns_gateway="$(resolved_host_var "${host_name}" "dns_gateway")"
  if [[ "${internal_dns_status}" == "operational" ]]; then
    if [[ "${internal_dns_enabled}" != "true" ]]; then
      ci_die "host ${host_name}: internal_dns.status=operational 但 internal_dns.enabled 不为 true"
    fi
    if [[ "${dns_gateway}" != "true" ]]; then
      ci_die "host ${host_name}: internal_dns.status=operational 但 dns_gateway 不为 true"
    fi
    ci_log "  ${host_name}: internal_dns operational OK"
  fi

  hub_docker_enabled="$(resolved_host_var "${host_name}" "hub_docker.enabled")"
  hub_docker_status="$(resolved_host_var "${host_name}" "hub_docker.status")"
  docker_gateway="$(resolved_host_var "${host_name}" "docker_gateway")"
  docker_install_flag="$(resolved_host_var "${host_name}" "docker_install")"
  ci_log "  ${host_name}: hub_docker.enabled=${hub_docker_enabled:-<unset>} status=${hub_docker_status:-<unset>}"

  if [[ "${hub_docker_status}" == "operational" ]]; then
    if [[ "${hub_docker_enabled}" != "true" ]]; then
      ci_die "host ${host_name}: hub_docker.status=operational 但 hub_docker.enabled 不为 true"
    fi
    if [[ "${docker_gateway}" != "true" ]]; then
      ci_die "host ${host_name}: hub_docker.status=operational 但 docker_gateway 不为 true"
    fi
    if [[ "${docker_install_flag}" != "true" ]]; then
      ci_die "host ${host_name}: hub_docker.status=operational 但 docker_install 不为 true"
    fi
    ci_log "  ${host_name}: hub_docker operational OK (Hub Docker 已登记)"
  fi

  jumpserver_enabled="$(resolved_host_var "${host_name}" "jumpserver.enabled")"
  jumpserver_status="$(resolved_host_var "${host_name}" "jumpserver.status")"
  jumpserver_gateway="$(resolved_host_var "${host_name}" "jumpserver_gateway")"
  ci_log "  ${host_name}: jumpserver.enabled=${jumpserver_enabled:-<unset>} status=${jumpserver_status:-<unset>}"

  if [[ "${jumpserver_status}" == "operational" ]]; then
    if [[ "${jumpserver_enabled}" != "true" ]]; then
      ci_die "host ${host_name}: jumpserver.status=operational 但 jumpserver.enabled 不为 true"
    fi
    if [[ "${jumpserver_gateway}" != "true" ]]; then
      ci_die "host ${host_name}: jumpserver.status=operational 但 jumpserver_gateway 不为 true"
    fi
    js_deploy="$(resolved_host_var "${host_name}" "nginx.jumpserver.deploy_status")"
    if [[ "${js_deploy}" != "ready" ]]; then
      ci_die "host ${host_name}: jumpserver.status=operational 但 nginx.jumpserver.deploy_status=${js_deploy:-<unset>}，应为 ready"
    fi
    ci_log "  ${host_name}: jumpserver operational OK (JumpServer 已登记)"
  fi
done

# -----------------------------------------------------------------------------
# wireguard_peers 组 — ci-01 等本机 Client 变量门禁
# -----------------------------------------------------------------------------
mapfile -t wg_peer_hosts < <(
  ci_cd ansible wireguard_peers -i "${MGMT_INVENTORY}" --list-hosts 2>/dev/null \
    | awk '/^[[:space:]]+[a-zA-Z0-9_-]+/ && !/\(/ { print $1 }' \
    | sort -u
)

if [[ ${#wg_peer_hosts[@]} -eq 0 ]]; then
  ci_log "WARN: no hosts in wireguard_peers group"
else
  ci_log "Checking ${#wg_peer_hosts[@]} host(s) in wireguard_peers group..."
  for host_name in "${wg_peer_hosts[@]}"; do
    conn="$(resolved_host_var "${host_name}" "ansible_connection")"
    wg_peer="$(resolved_host_var "${host_name}" "wireguard_peer")"
    wg_peer_name="$(resolved_host_var "${host_name}" "wireguard_peer_name")"
    limited_sudo="$(resolved_host_var "${host_name}" "wireguard_client_use_limited_sudo")"

    [[ "${conn}" == "local" ]] \
      || ci_die "host ${host_name}: wireguard_peers must use ansible_connection=local (got ${conn:-<unset>})"
    [[ "${wg_peer}" == "true" ]] \
      || ci_die "host ${host_name}: wireguard_peer must be true (see host_vars/${host_name}.yml)"
    [[ -n "${wg_peer_name}" && "${wg_peer_name}" != "null" ]] \
      || ci_die "host ${host_name}: wireguard_peer_name is empty"

    ci_log "  ${host_name}: connection=${conn} peer_name=${wg_peer_name} limited_sudo=${limited_sudo:-<unset>} OK"
  done
fi

ci_log "inventory-check-mgmt OK"
