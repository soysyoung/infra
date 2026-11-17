#!/usr/bin/env bash
# 삭제 08. 감시 서비스(mlops-watchdog)와 08-boot-resilience.sh 가 만든 것을 지운다.
#
# 클러스터가 사라지면 감시 서비스는 할 일이 없고 /etc/mlops/cp-ip 가 낡은 값이 되므로 07-1(port-forward)보다 먼저 지운다.
# 아래 두 항목은 2026-10-27 오전의 이전 버전 08 이 만든 것이다 (docker 시작 전 tailscale wait, port-forward 전용 kubeconfig).
# 그 버전을 설치한 PC 에 남아 있어서 함께 지운다. 없으면 건너뛴다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

paths=(
  /etc/systemd/system/mlops-watchdog.timer
  /etc/systemd/system/mlops-watchdog.service
  /usr/local/sbin/mlops-watchdog
  /etc/mlops
  /etc/systemd/system/docker.service.d/10-tailscale-wait.conf         # 이전 버전
  /etc/systemd/system/kubeflow-port-forward.service.d                 # 이전 버전 (전용 kubeconfig 를 쓰는 drop-in)
  "$HOME/.kube/mlops-local.config"                                    # 이전 버전
)
present=()
for p in "${paths[@]}"; do [ -e "$p" ] && present+=("$p"); done
if [ "${#present[@]}" = 0 ]; then
  log "08-boot-resilience 가 만든 것이 없어 건너뜁니다."; exit 0
fi
printf '    %s\n' "${present[@]}"
confirm "위 항목을 삭제하고 mlops-watchdog 를 중지합니다."

run sudo systemctl disable --now mlops-watchdog.timer || true
run sudo systemctl stop mlops-watchdog.service || true
run sudo rm -rf "${present[@]}"
run sudo rm -f /run/mlops-watchdog.fails /run/mlops-watchdog.down
run sudo rmdir /etc/systemd/system/docker.service.d 2>/dev/null || true   # 비어 있을 때만
run sudo systemctl daemon-reload
log "완료"
