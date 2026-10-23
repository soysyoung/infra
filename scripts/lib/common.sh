#!/usr/bin/env bash
# 공통 함수. 각 스크립트에서 'source "$(dirname "$0")/lib/common.sh"' 로 읽는다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/versions.env"
# shellcheck source=/dev/null
source "$ROOT/cluster.env"

CLUSTER=mlops
KUBECONFIG_FILE="$HOME/.kube/kind-$CLUSTER.yaml"
GPU_LABEL=nvidia.com/gpu.present=true   # GPU 노드에만 붙는 라벨 (05-1 이 부여)

log() { echo "==> $*"; }

# GPU 노드 이름. kind 노드 이름은 Docker 컨테이너 이름과 같다.
gpu_node() { kubectl get node -l "$GPU_LABEL" -o jsonpath='{.items[0].metadata.name}'; }
die() { echo "오류: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null || die "$1 가 필요합니다. ${2:-}"; }

require_systemd() {
  [ -d /run/systemd/system ] || die "systemd 가 실행 중이 아닙니다. 01-wsl-systemd.sh 와 'wsl --shutdown' 을 먼저 하세요."
}
