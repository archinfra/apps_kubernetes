#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="k8s-sealos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/common"
WORKDIR="/tmp/${APP_NAME}-installer.$$"
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

note() {
  echo -e "${YELLOW}[NOTE]${NC} $*"
}

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

wants_fast_help() {
  local arg

  if [[ $# -eq 0 ]]; then
    return 0
  fi

  for arg in "$@"; do
    case "${arg}" in
      --)
        break
        ;;
      -h|--help)
        return 0
        ;;
    esac
  done

  return 1
}

show_fast_help() {
  cat <<'EOF'
OneKube Kubernetes Offline Installer

Usage:
  ./k8s-sealos-linux-<arch>-<bundle>.run install|reset|precheck|show-defaults [options] [-- <extra sealos args>]

Commands:
  install                     Install Kubernetes cluster
  reset                       Reset Kubernetes cluster
  precheck                    Run prechecks only
  show-defaults               Show built-in defaults

SSH Options:
  --user <username>           SSH username
  --passwd <password>         SSH password
  --pk <path>                 SSH private key path
  --pk-passwd <password>      SSH private key passphrase
  --port <port>               SSH port, default: 22

Install Options:
  --masters <ip,ip>           Master node IP list
  --nodes <ip,ip>             Worker node IP list
  --data-root <path>          Sealos data root, default: /data
  --cri-data <path>           Container runtime data root, default: /data/containerd
  --cni-helm-opts <args>      Extra Cilium ExtraValues value
  --registry <registry>       Override image registry prefix
  --k8s-version <tag>         Override Kubernetes image tag
  --helm-version <tag>        Override Helm image tag
  --cni-version <tag>         Override Cilium image tag
  --skip-image-load           Skip local image load
  --skip-binary-install       Skip Sealos binary install
  --skip-precheck             Skip prechecks
  --dry-run                   Print final sealos command only
  --force                     Pass --force to sealos and skip confirm
  --debug                     Enable debug output
  -y, --yes                   Auto confirm
  -h, --help                  Show help

Examples:
  ./k8s-sealos-linux-amd64-full.run install --masters 10.0.0.11 --nodes 10.0.0.21 --passwd 'your-password' --yes
  ./k8s-sealos-linux-amd64-full.run install --masters 10.0.0.11 --nodes 10.0.0.21 --user root --pk /root/.ssh/id_rsa --yes
  ./k8s-sealos-linux-amd64-full.run precheck --masters 10.0.0.11 --nodes 10.0.0.21 --user root --pk /root/.ssh/id_rsa --yes

Notes:
  - Help mode is fast and does not extract the full package.
  - Runtime actions extract payload only when needed.
  - Default Cilium version is 1.18.1.
  - Default install adds:
      -e ExtraValues=kubeProxyReplacement=false
EOF
}

bootstrap_payload() {
  local payload_line

  info "Preparing installer payload from self-extracting package"
  note "Full offline bundles can take a while to unpack on slower disks"

  mkdir -p "${WORKDIR}"
  payload_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$0")"
  [[ -n "${payload_line}" ]] || {
    echo "[ERROR] package payload marker not found" >&2
    exit 1
  }

  tail -n +"${payload_line}" "$0" | tar -xz -C "${WORKDIR}" || {
    echo "[ERROR] failed to extract payload" >&2
    exit 1
  }

  info "Installer payload is ready: ${WORKDIR}"
}

if wants_fast_help "$@"; then
  show_fast_help
  exit 0
fi

if [[ -f "${COMMON_DIR}/install-common.sh" && -f "${SCRIPT_DIR}/versions.env" ]]; then
  export K8S_SEALOS_CONTEXT_DIR="${SCRIPT_DIR}"
  # shellcheck disable=SC1091
  source "${COMMON_DIR}/install-common.sh"
else
  bootstrap_payload
  export K8S_SEALOS_CONTEXT_DIR="${WORKDIR}"
  # shellcheck disable=SC1091
  source "${WORKDIR}/lib/install-common.sh"
fi

k8s_sealos_install_main "$@"
exit 0
__PAYLOAD_BELOW__
