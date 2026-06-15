#!/usr/bin/env bash
# =============================================================================
# GitHub Self-hosted Runner 注册（ci-01 / yax）
# =============================================================================
#
# 【用途】
#   在 ci-01 上安装并注册 GitHub Actions Runner，标签与 deploy.yml 对齐：
#     self-hosted, dev, aliyun
#
# 【前提】
#   - WireGuard ci-01 ↔ Hub 已 operational（建议先跑 stage-f2-5-followup.sh）
#   - 从 GitHub 获取一次性注册 Token：
#     Settings → Actions → Runners → New self-hosted runner → Linux
#
# 【用法】
#   export RUNNER_REGISTRATION_TOKEN="AAAA..."
#   # 可选：export GITHUB_REPO="owner/repo"  默认从 git remote 推断
#   ./scripts/mgmt/register-github-runner.sh
#
#   仅查看步骤、不安装：
#   ./scripts/mgmt/register-github-runner.sh --dry-run
#
# 【安装位置】
#   ~/actions-runner/  （deploy 用户）
#   systemd 服务名：actions.runner.*.service
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER_HOME="${RUNNER_HOME:-${HOME}/actions-runner}"
DRY_RUN=false

# 与 ci-01.yaml / deploy.yml 一致
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,dev,aliyun}"
RUNNER_NAME="${RUNNER_NAME:-ci-01-yax}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Environment:
  RUNNER_REGISTRATION_TOKEN   必填（GitHub 一次性 token）
  GITHUB_REPO                 可选，默认 git remote origin → owner/repo
  RUNNER_HOME                 默认 ~/actions-runner
  RUNNER_NAME                 默认 ci-01-yax
  RUNNER_LABELS               默认 self-hosted,dev,aliyun

Options:
  --dry-run    只打印将执行的步骤
  -h, --help   显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

detect_github_repo() {
  local url
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  if [[ "$url" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    echo "${BASH_REMATCH[1]%.git}"
    return 0
  fi
  echo ""
}

GITHUB_REPO="${GITHUB_REPO:-$(detect_github_repo)}"
[[ -n "$GITHUB_REPO" ]] || {
  echo "ERROR: cannot detect GITHUB_REPO; set GITHUB_REPO=owner/repo" >&2
  exit 1
}

if [[ "$DRY_RUN" == "true" ]]; then
  cat <<EOF
[dry-run] Would register runner:
  repo:    https://github.com/${GITHUB_REPO}
  home:    ${RUNNER_HOME}
  name:    ${RUNNER_NAME}
  labels:  ${RUNNER_LABELS}
  token:   (RUNNER_REGISTRATION_TOKEN)

Steps:
  1. curl -o actions-runner-linux-x64.tar.gz (latest from GitHub)
  2. tar xzf && ./config.sh --url ... --token ... --unattended
  3. ./svc.sh install ${USER} && ./svc.sh start
EOF
  exit 0
fi

[[ -n "${RUNNER_REGISTRATION_TOKEN:-}" ]] || {
  echo "ERROR: set RUNNER_REGISTRATION_TOKEN from GitHub → Settings → Actions → Runners" >&2
  exit 1
}

# 建议 WG 已通（非强制）
if command -v wg >/dev/null 2>&1 && sudo wg show wg0 2>/dev/null | grep -q 'latest handshake'; then
  echo "OK: WireGuard handshake present"
else
  echo "WARN: wg0 handshake not detected — Runner 仍可安装，但 deploy 经 WG 的路径未验证" >&2
fi

mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME"

ARCH="x64"
RUNNER_VERSION="${RUNNER_VERSION:-2.323.0}"
RUNNER_TARBALL="actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TARBALL}"

if [[ ! -f "./config.sh" ]]; then
  echo "Downloading ${RUNNER_URL} ..."
  curl -fsSL -o "$RUNNER_TARBALL" "$RUNNER_URL"
  tar xzf "$RUNNER_TARBALL"
  rm -f "$RUNNER_TARBALL"
fi

if [[ -f "./.runner" ]]; then
  echo "Runner already configured in ${RUNNER_HOME} (.runner exists)"
  echo "To re-register: remove ${RUNNER_HOME} or run ./config.sh remove with token"
else
  ./config.sh \
    --url "https://github.com/${GITHUB_REPO}" \
    --token "$RUNNER_REGISTRATION_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --unattended \
    --replace
fi

# 安装为 deploy 用户的 systemd 服务
sudo ./svc.sh install "$USER"
sudo ./svc.sh start

echo ""
echo "Runner registered:"
echo "  repo:   https://github.com/${GITHUB_REPO}"
echo "  labels: ${RUNNER_LABELS}"
echo "  home:   ${RUNNER_HOME}"
echo ""
echo "Verify: GitHub → Settings → Actions → Runners → should show Idle"
echo "Update docs/assets/ci-01.yaml → github_runner.status: registered"
