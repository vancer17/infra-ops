#!/usr/bin/env bash
# =============================================================================
# scripts/ci/ansible-syntax.sh — Ansible Playbook 语法检查
#                                          （对应 ci.yml job: ansible-syntax）
# =============================================================================
#
# 【检查内容】
#   1. 若存在 ansible/site.yml → --syntax-check
#   2. 若存在 ansible/playbooks/*.yml → 逐个 --syntax-check
#   3. （附加）ansible-inventory 解析 Dev inventory，确认 Jinja2 变量可展开
#
#   syntax-check 会加载 inventory、roles、模板，但不连接 SSH。
#
# 【前置依赖】
#   ansible、Galaxy collections
#   → ./scripts/ci/install-deps.sh ansible
#
# 【用法】
#   ./scripts/ci/ansible-syntax.sh
#
# 【inventory】
#   默认 -i ansible/inventories/dev/（与 ansible.cfg、deploy.yml 一致）
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd ansible-playbook
ci_require_cmd ansible-inventory

# -----------------------------------------------------------------------------
# syntax_check_playbook — 对单个 playbook 执行 --syntax-check
# -----------------------------------------------------------------------------
syntax_check_playbook() {
  local playbook="$1"
  ci_log "Syntax check: ${playbook}"
  ci_cd ansible-playbook "${playbook}" \
    --syntax-check \
    -i "${CI_ANSIBLE_INVENTORY}"
}

# -----------------------------------------------------------------------------
# Step 1 — site.yml（若存在）
# -----------------------------------------------------------------------------
site_playbook="${CI_REPO_ROOT}/ansible/site.yml"
if [[ -f "${site_playbook}" ]]; then
  syntax_check_playbook "ansible/site.yml"
else
  ci_skip "ansible/site.yml not found"
fi

# -----------------------------------------------------------------------------
# Step 2 — playbooks/*.yml
# -----------------------------------------------------------------------------
playbooks_dir="${CI_REPO_ROOT}/ansible/playbooks"
if [[ -d "${playbooks_dir}" ]]; then
  shopt -s nullglob
  playbooks=("${playbooks_dir}"/*.yml "${playbooks_dir}"/*.yaml)
  shopt -u nullglob

  if [[ ${#playbooks[@]} -eq 0 ]]; then
    ci_skip "no playbooks under ${playbooks_dir}"
  else
    for playbook in "${playbooks[@]}"; do
      [[ -f "${playbook}" ]] || continue
      # 传入相对 repo root 的路径，与 CI 原逻辑一致
      rel="${playbook#"${CI_REPO_ROOT}/"}"
      syntax_check_playbook "${rel}"
      # bootstrap / ssh-keys 使用 dev:mgmt，额外用 mgmt inventory 做 syntax-check
      if [[ -d "${CI_ANSIBLE_INVENTORY_MGMT}" ]] \
        && [[ "${rel}" == ansible/playbooks/bootstrap.yml || "${rel}" == ansible/playbooks/ssh-keys.yml ]]; then
        ci_log "Syntax check (mgmt inventory): ${rel}"
        ci_cd ansible-playbook "${rel}" \
          --syntax-check \
          -i "${CI_ANSIBLE_INVENTORY_MGMT}"
      fi
    done
  fi
else
  ci_skip "ansible/playbooks/ not found"
fi

# -----------------------------------------------------------------------------
# Step 3 — inventory 解析（附加门禁，捕获 Jinja2/ansible_host 错误）
# -----------------------------------------------------------------------------
ci_log "Inventory graph check: ${CI_ANSIBLE_INVENTORY}"
ci_cd ansible-inventory -i "${CI_ANSIBLE_INVENTORY}" --graph >/dev/null

# 对 dev 组内已知主机做 host 变量展开抽查
for host in dev-01 dev-02; do
  if ci_cd ansible-inventory -i "${CI_ANSIBLE_INVENTORY}" --host "${host}" >/dev/null 2>&1; then
    ci_log "Inventory host vars OK: ${host}"
  else
    ci_skip "host ${host} not in inventory (optional)"
  fi
done

# -----------------------------------------------------------------------------
# Step 4 — mgmt inventory 解析（Hub 纳管；捕获 Jinja2/ansible_host 错误）
# -----------------------------------------------------------------------------
mgmt_inventory="${CI_ANSIBLE_INVENTORY_MGMT}"
if [[ -d "${mgmt_inventory}" ]]; then
  ci_log "Mgmt inventory graph check: ${mgmt_inventory}"
  ci_cd ansible-inventory -i "${mgmt_inventory}" --graph >/dev/null
  if ci_cd ansible-inventory -i "${mgmt_inventory}" --host hub-01 >/dev/null 2>&1; then
    ci_log "Mgmt inventory host vars OK: hub-01"
  else
    ci_skip "host hub-01 not in mgmt inventory"
  fi
else
  ci_skip "mgmt inventory not found: ${mgmt_inventory}"
fi

ci_log "ansible-syntax OK"
