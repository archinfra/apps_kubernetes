#!/usr/bin/env bash

set -Eeuo pipefail

: "${K8S_SEALOS_CONTEXT_DIR:?K8S_SEALOS_CONTEXT_DIR is required}"

APP_NAME="${APP_NAME:-k8s-sealos}"
CONTEXT_DIR="${K8S_SEALOS_CONTEXT_DIR}"
SYSTEM_BIN_DIR="/usr/local/bin"
STATE_DIR="/etc/${APP_NAME}"
ENV_FILE="${STATE_DIR}/cluster.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ACTION="install"
MASTERS=""
NODES=""
PASSWD=""
PORT="22"
DATA_ROOT="/data"
CRI_DATA="/data/containerd"

SEALOS_VERSION=""
IMAGE_REGISTRY=""
K8S_IMAGE_NAME=""
K8S_VERSION=""
HELM_IMAGE_NAME=""
HELM_VERSION=""
CNI_IMAGE_NAME=""
CNI_VERSION=""
ARCH="${ARCH:-unknown}"
PLATFORM="${PLATFORM:-unknown}"

FORCE="false"
DEBUG="false"
AUTO_YES="false"
SKIP_IMAGE_LOAD="false"
SKIP_BINARY_INSTALL="false"
SKIP_PRECHECK="false"
DRY_RUN="false"

SEALOS_EXTRA_ARGS=()

PAYLOAD_ROOT=""
BIN_DIR=""
IMAGE_DIR=""
SEALOS_RUNTIME_ROOT=""
SEALOS_DATA_ROOT=""
K8S_IMAGE=""
HELM_IMAGE=""
CNI_IMAGE=""

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

usage() {
  cat <<EOF
用法:
  $(basename "$0") install|reset|precheck|show-defaults [选项] [-- <额外 sealos 参数>]

命令:
  install             安装 Kubernetes 集群
  reset               重置 Kubernetes 集群
  precheck            检查安装包、参数和本机环境
  show-defaults       显示默认版本矩阵和参数

常用选项:
  --masters <ip,ip>           Master 节点 IP，多个地址用逗号分隔
  --nodes <ip,ip>             Worker 节点 IP，多个地址用逗号分隔
  --passwd <password>         SSH 密码；如果已做免密可以不填
  --port <port>               SSH 端口，默认 22
  --data-root <path>          Sealos 数据根目录，默认 /data
  --cri-data <path>           容器运行时数据目录，默认 /data/containerd
  --registry <registry>       镜像仓库前缀，默认 registry.cn-shanghai.aliyuncs.com/labring
  --k8s-version <tag>         Kubernetes 镜像标签
  --helm-version <tag>        Helm 镜像标签
  --cni-version <tag>         Cilium 镜像标签
  --skip-image-load           跳过本地镜像导入
  --skip-binary-install       跳过安装 Sealos 二进制
  --skip-precheck             跳过安装前检查
  --dry-run                   只打印最终 sealos 命令，不真正执行
  --force                     透传 --force 给 sealos，同时跳过交互确认
  --debug                     透传 --debug 给 sealos，并打开脚本调试信息
  -y, --yes                   自动确认
  -h, --help                  显示帮助

说明:
  1. 直接在仓库目录执行 install.sh 时，会使用当前目录下的 bin/ 和 images/
  2. 执行 .run 安装包时，会先自动解压 payload 再执行同一套安装逻辑
  3. 环境变量统一写入 ${ENV_FILE}，不再污染 ~/.bashrc
EOF
}

refresh_runtime_values() {
  SEALOS_RUNTIME_ROOT="${DATA_ROOT}/.sealos"
  SEALOS_DATA_ROOT="${DATA_ROOT}/sealos"
  K8S_IMAGE="${IMAGE_REGISTRY}/${K8S_IMAGE_NAME}:${K8S_VERSION}"
  HELM_IMAGE="${IMAGE_REGISTRY}/${HELM_IMAGE_NAME}:${HELM_VERSION}"
  CNI_IMAGE="${IMAGE_REGISTRY}/${CNI_IMAGE_NAME}:${CNI_VERSION}"
}

load_runtime_metadata() {
  local versions_file="${CONTEXT_DIR}/versions.env"
  local manifest_file="${CONTEXT_DIR}/release-manifest.env"
  local binary

  [[ -f "${versions_file}" ]] || die "缺少版本文件: ${versions_file}"
  [[ -d "${CONTEXT_DIR}/bin" ]] || die "缺少二进制目录: ${CONTEXT_DIR}/bin"
  [[ -d "${CONTEXT_DIR}/images" ]] || die "缺少镜像目录: ${CONTEXT_DIR}/images"

  # shellcheck disable=SC1090
  source "${versions_file}"

  if [[ -f "${manifest_file}" ]]; then
    # shellcheck disable=SC1090
    source "${manifest_file}"
  fi

  PAYLOAD_ROOT="${CONTEXT_DIR}"
  BIN_DIR="${CONTEXT_DIR}/bin"
  IMAGE_DIR="${CONTEXT_DIR}/images"

  for binary in sealos sealctl image-cri-shim lvscare; do
    if [[ -f "${BIN_DIR}/${binary}" ]]; then
      chmod +x "${BIN_DIR}/${binary}" || true
    fi
  done

  refresh_runtime_values
}

parse_args() {
  [[ $# -eq 0 ]] && {
    usage
    exit 0
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|reset|precheck|show-defaults)
        ACTION="$1"
        shift
        ;;
      --masters)
        MASTERS="$2"
        shift 2
        ;;
      --nodes)
        NODES="$2"
        shift 2
        ;;
      --passwd)
        PASSWD="$2"
        shift 2
        ;;
      --port)
        PORT="$2"
        shift 2
        ;;
      --data-root)
        DATA_ROOT="$2"
        shift 2
        ;;
      --cri-data|--criData)
        CRI_DATA="$2"
        shift 2
        ;;
      --registry)
        IMAGE_REGISTRY="$2"
        shift 2
        ;;
      --k8s-version)
        K8S_VERSION="$2"
        shift 2
        ;;
      --helm-version)
        HELM_VERSION="$2"
        shift 2
        ;;
      --cni-version)
        CNI_VERSION="$2"
        shift 2
        ;;
      --skip-image-load)
        SKIP_IMAGE_LOAD="true"
        shift
        ;;
      --skip-binary-install)
        SKIP_BINARY_INSTALL="true"
        shift
        ;;
      --skip-precheck)
        SKIP_PRECHECK="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --force)
        FORCE="true"
        AUTO_YES="true"
        shift
        ;;
      --debug)
        DEBUG="true"
        shift
        ;;
      -y|--yes)
        AUTO_YES="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          SEALOS_EXTRA_ARGS+=("$1")
          shift
        done
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done

  refresh_runtime_values
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 用户执行"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

prepare_runtime_layout() {
  load_runtime_metadata
  log "使用运行目录: ${PAYLOAD_ROOT}"
}

validate_args() {
  case "${ACTION}" in
    install|reset|precheck)
      [[ -n "${MASTERS}" ]] || die "请通过 --masters 指定至少一个 master 节点"
      ;;
  esac
}

show_defaults() {
  cat <<EOF
架构:               ${ARCH}
Sealos 版本:        ${SEALOS_VERSION}
Kubernetes 镜像:    ${K8S_IMAGE}
Helm 镜像:          ${HELM_IMAGE}
Cilium 镜像:        ${CNI_IMAGE}

默认参数:
  data-root:        ${DATA_ROOT}
  cri-data:         ${CRI_DATA}
  ssh-port:         ${PORT}
EOF
}

run_prechecks() {
  local probe_dir

  require_cmd tar
  require_cmd awk
  require_cmd tail
  require_cmd grep
  require_cmd install
  require_cmd df

  [[ -f "${BIN_DIR}/sealos" ]] || die "缺少 sealos 二进制: ${BIN_DIR}/sealos"
  [[ -f "${BIN_DIR}/sealctl" ]] || warn "缺少 sealctl 二进制: ${BIN_DIR}/sealctl"
  [[ -f "${IMAGE_DIR}/image.json" ]] || warn "缺少 image.json，继续执行但不利于排障"

  probe_dir="${DATA_ROOT}"
  while [[ ! -d "${probe_dir}" && "${probe_dir}" != "/" ]]; do
    probe_dir="$(dirname "${probe_dir}")"
  done
  [[ -d "${probe_dir}" ]] || probe_dir="/"

  log "安装前检查通过"
  log "  数据目录检查位置: ${probe_dir}"
  df -h "${probe_dir}" | tail -n 1
}

confirm_plan() {
  [[ "${AUTO_YES}" == "true" ]] && return 0

  cat <<EOF
==================================================
操作类型:            ${ACTION}
Master 节点:         ${MASTERS}
Worker 节点:         ${NODES:-<none>}
SSH 端口:            ${PORT}
数据目录:            ${DATA_ROOT}
CRI 数据目录:        ${CRI_DATA}
Sealos 版本:         ${SEALOS_VERSION}
Kubernetes 镜像:     ${K8S_IMAGE}
Helm 镜像:           ${HELM_IMAGE}
Cilium 镜像:         ${CNI_IMAGE}
跳过二进制安装:      ${SKIP_BINARY_INSTALL}
跳过镜像导入:        ${SKIP_IMAGE_LOAD}
Dry run:             ${DRY_RUN}
==================================================
EOF

  read -r -p "确认继续执行? [y/N]: " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "操作已取消"
}

backup_if_exists() {
  local target="$1"

  if [[ -f "${target}" ]]; then
    mv -f "${target}" "${target}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

install_binaries() {
  local binary

  mkdir -p "${SYSTEM_BIN_DIR}"

  for binary in sealos sealctl image-cri-shim lvscare; do
    [[ -f "${BIN_DIR}/${binary}" ]] || continue
    backup_if_exists "${SYSTEM_BIN_DIR}/${binary}"
    install -m 0755 "${BIN_DIR}/${binary}" "${SYSTEM_BIN_DIR}/${binary}"
    success "已安装二进制: ${SYSTEM_BIN_DIR}/${binary}"
  done
}

ensure_sealos_available() {
  command -v sealos >/dev/null 2>&1 || die "未找到 sealos 命令"
  log "Sealos 版本: $(sealos version 2>/dev/null | head -n 1 || echo unknown)"
}

load_images() {
  local image_tar
  local loaded=0

  if ! compgen -G "${IMAGE_DIR}/*.tar" >/dev/null 2>&1; then
    warn "未发现镜像 tar 文件，跳过镜像导入"
    return 0
  fi

  for image_tar in "${IMAGE_DIR}"/*.tar; do
    log "导入镜像: $(basename "${image_tar}")"
    if sealos load -i "${image_tar}"; then
      loaded=$((loaded + 1))
    else
      warn "镜像导入失败: $(basename "${image_tar}")"
    fi
  done

  [[ "${loaded}" -gt 0 ]] || warn "没有镜像成功导入，请确认镜像包是否完整"
}

write_environment_file() {
  mkdir -p "${STATE_DIR}"

  cat > "${ENV_FILE}" <<EOF
# Generated by ${APP_NAME}
export ARCH="${ARCH}"
export PLATFORM="${PLATFORM}"
export SEALOS_VERSION="${SEALOS_VERSION}"
export IMAGE_REGISTRY="${IMAGE_REGISTRY}"
export K8S_IMAGE_NAME="${K8S_IMAGE_NAME}"
export K8S_VERSION="${K8S_VERSION}"
export HELM_IMAGE_NAME="${HELM_IMAGE_NAME}"
export HELM_VERSION="${HELM_VERSION}"
export CNI_IMAGE_NAME="${CNI_IMAGE_NAME}"
export CNI_VERSION="${CNI_VERSION}"
export SEALOS_RUNTIME_ROOT="${SEALOS_RUNTIME_ROOT}"
export SEALOS_DATA_ROOT="${SEALOS_DATA_ROOT}"
export SEALOS_SCP_CHECKSUM="false"
export SEALOS_REGISTRY_SKIP_TLS="true"
export DATA_ROOT="${DATA_ROOT}"
export CRI_DATA="${CRI_DATA}"
export MASTERS="${MASTERS}"
export NODES="${NODES}"
EOF

  success "已写入环境文件: ${ENV_FILE}"
}

run_sealos() {
  local -a env_cmd
  local -a sealos_cmd

  env_cmd=(
    env
    "SEALOS_RUNTIME_ROOT=${SEALOS_RUNTIME_ROOT}"
    "SEALOS_DATA_ROOT=${SEALOS_DATA_ROOT}"
    "SEALOS_SCP_CHECKSUM=false"
    "SEALOS_REGISTRY_SKIP_TLS=true"
  )

  if [[ "${ACTION}" == "install" ]]; then
    sealos_cmd=(sealos run "${K8S_IMAGE}" "${HELM_IMAGE}" "${CNI_IMAGE}")
    sealos_cmd+=(--masters "${MASTERS}")
    [[ -n "${NODES}" ]] && sealos_cmd+=(--nodes "${NODES}")
    [[ -n "${PASSWD}" ]] && sealos_cmd+=(--passwd "${PASSWD}")
    [[ -n "${PORT}" ]] && sealos_cmd+=(--port "${PORT}")
    sealos_cmd+=(-e "criData=${CRI_DATA}")
  else
    sealos_cmd=(sealos reset)
    sealos_cmd+=(--masters "${MASTERS}")
    [[ -n "${NODES}" ]] && sealos_cmd+=(--nodes "${NODES}")
    [[ -n "${PASSWD}" ]] && sealos_cmd+=(--passwd "${PASSWD}")
    [[ -n "${PORT}" ]] && sealos_cmd+=(--port "${PORT}")

    if [[ "${AUTO_YES}" == "true" && "${FORCE}" != "true" ]]; then
      sealos_cmd+=(--force)
    fi
  fi

  [[ "${FORCE}" == "true" ]] && sealos_cmd+=(--force)
  [[ "${DEBUG}" == "true" ]] && sealos_cmd+=(--debug)

  if [[ "${#SEALOS_EXTRA_ARGS[@]}" -gt 0 ]]; then
    sealos_cmd+=("${SEALOS_EXTRA_ARGS[@]}")
  fi

  log "执行命令:"
  printf '  %q ' "${env_cmd[@]}" "${sealos_cmd[@]}"
  printf '\n'

  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "当前为 dry-run 模式，未真正执行 sealos"
    return 0
  fi

  "${env_cmd[@]}" "${sealos_cmd[@]}"
}

show_post_install_info() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    cat <<EOF

dry-run 已完成，未真正执行集群操作。
你可以基于上面打印出的 sealos 命令继续调整参数，然后再正式执行。

环境变量文件:
  ${ENV_FILE}
EOF
    return
  fi

  cat <<EOF

集群操作已完成。

后续常用命令:
  source ${ENV_FILE}
  kubectl get nodes -o wide
  sealos images

环境变量文件:
  ${ENV_FILE}
EOF
}

k8s_sealos_install_main() {
  parse_args "$@"

  if [[ "${DEBUG}" == "true" ]]; then
    set -x
  fi

  prepare_runtime_layout

  if [[ "${ACTION}" == "show-defaults" ]]; then
    show_defaults
    exit 0
  fi

  require_root
  validate_args

  if [[ "${SKIP_PRECHECK}" != "true" ]]; then
    run_prechecks
  fi

  if [[ "${ACTION}" == "precheck" ]]; then
    success "precheck 完成"
    exit 0
  fi

  confirm_plan

  if [[ "${SKIP_BINARY_INSTALL}" != "true" ]]; then
    install_binaries
  fi

  ensure_sealos_available

  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_LOAD}" != "true" ]]; then
    load_images
  fi

  write_environment_file
  run_sealos
  show_post_install_info
}
