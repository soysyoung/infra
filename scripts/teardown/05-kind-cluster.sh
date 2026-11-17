#!/usr/bin/env bash
# 삭제 05. kind 클러스터 삭제 (Kubeflow, device plugin, GPU 노드 설정이 함께 사라진다), kind/kubectl, inotify 설정
#
# kind delete cluster 는 ~/.kube/config 의 해당 항목(cluster/context/user)도 정리한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

confirm "클러스터 '$CLUSTER' 를 삭제합니다. Kubeflow 를 포함한 모든 워크로드와 그 안의 데이터(PV)가 사라집니다."

if type -P kind >/dev/null && docker info >/dev/null 2>&1 && kind get clusters | grep -qx "$CLUSTER"; then
  run kind delete cluster --name "$CLUSTER"
else
  log "클러스터 '$CLUSTER' 가 없어서 건너뜁니다."
fi

run sudo rm -f /usr/local/bin/kind /usr/local/bin/kubectl
# 05-1 이 올린 inotify 한도를 되돌린다. 128 은 설치 전 이 PC(WSL Ubuntu 24.04)의 기본값이었다.
run sudo rm -f /etc/sysctl.d/99-kind-inotify.conf
run sudo sysctl -w fs.inotify.max_user_instances=128
log "완료"
