#!/usr/bin/env bash
# 삭제 06. Kubeflow 설치에 쓴 로컬 파일 정리 (공식 저장소 클론, kustomize)
#
# Kubeflow 워크로드는 클러스터 안에 있어서 삭제 05(클러스터 삭제)와 함께 사라진다.
# 클러스터는 두고 Kubeflow 만 지우는 용도는 지원하지 않는다 (CRD/finalizer 때문에 삭제가 멈출 수 있다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

confirm "Kubeflow 설치용 클론(~/.cache/infra)과 kustomize 를 삭제합니다."
run rm -rf "$HOME/.cache/infra"
run sudo rm -f /usr/local/bin/kustomize
log "완료"
