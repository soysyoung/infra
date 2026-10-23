#!/usr/bin/env bash
# 공통 함수. 각 스크립트에서 'source "$(dirname "$0")/lib/common.sh"' 로 읽는다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/versions.env"
# shellcheck source=/dev/null
source "$ROOT/cluster.env"

CLUSTER=mlops
# kind 는 접속 정보를 공식 기본값(~/.kube/config)에 병합하고 current-context 를 바꾼다.
# 나중에 다른 클러스터가 생겨도 엉뚱한 곳에 적용하지 않도록 kubectl 은 항상 이 클러스터의 컨텍스트를 명시한다.
kubectl() { command kubectl --context "kind-$CLUSTER" "$@"; }
GPU_LABEL=nvidia.com/gpu.present=true   # GPU 노드에만 붙는 라벨 (05-1 이 부여)

log() { echo "==> $*"; }

# GPU 노드 이름. kind 노드 이름은 Docker 컨테이너 이름과 같다.
gpu_node() { kubectl get node -l "$GPU_LABEL" -o jsonpath='{.items[0].metadata.name}'; }
die() { echo "오류: $*" >&2; exit 1; }

# type -P: 위에서 정의한 kubectl 함수가 아니라 실제 실행 파일이 있는지 본다.
require_cmd() { type -P "$1" >/dev/null || die "$1 가 필요합니다. ${2:-}"; }

require_systemd() {
  [ -d /run/systemd/system ] || die "systemd 가 실행 중이 아닙니다. 01-wsl-systemd.sh 와 'wsl --shutdown' 을 먼저 하세요."
}

# --- 삭제 스크립트(scripts/teardown/)용 ---
# DRY_RUN=1 이면 실행하지 않고 명령만 출력한다.
run() { if [ "${DRY_RUN:-}" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
# ASSUME_YES=1 이나 DRY_RUN=1 이 아니면 'yes' 를 입력해야 진행한다.
confirm() {
  [ "${ASSUME_YES:-}" = 1 ] || [ "${DRY_RUN:-}" = 1 ] && return 0
  read -r -p "$1 계속하려면 'yes' 를 입력: " answer || die "입력이 없어 취소했습니다."
  [ "$answer" = yes ] || die "취소했습니다."
}
