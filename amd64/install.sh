#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="k8s-sealos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"
WORKDIR="/tmp/${APP_NAME}-installer.$$"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

bootstrap_payload() {
  local payload_line

  mkdir -p "${WORKDIR}"
  payload_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$0")"
  [[ -n "${payload_line}" ]] || {
    echo "[ERROR] 未找到安装包 payload" >&2
    exit 1
  }

  tail -n +"${payload_line}" "$0" | tar -xz -C "${WORKDIR}" || {
    echo "[ERROR] 解压 payload 失败" >&2
    exit 1
  }
}

if [[ -f "${COMMON_DIR}/install-common.sh" && -f "${SCRIPT_DIR}/versions.env" && -d "${SCRIPT_DIR}/bin" ]]; then
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
