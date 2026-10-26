#!/usr/bin/env bash
# 삭제 07. tailnet 노출 서비스(port-forward 방식)를 지운다.
#
# 클러스터가 사라지면 이 서비스는 접속할 곳이 없어 5초마다 재시작만 반복하므로 05(클러스터 삭제)보다 먼저 지운다.
# NodePort 방식(extraPortMappings)은 클러스터와 함께 사라진다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

unit=/etc/systemd/system/kubeflow-port-forward.service
if [ ! -f "$unit" ]; then
  log "kubeflow-port-forward 서비스가 없어 건너뜁니다."; exit 0
fi
confirm "kubeflow-port-forward 서비스를 중지하고 삭제합니다."
run sudo systemctl disable --now kubeflow-port-forward
run sudo rm -f "$unit"
run sudo systemctl daemon-reload
log "완료"
