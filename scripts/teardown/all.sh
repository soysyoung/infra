#!/usr/bin/env bash
# 삭제: WSL 안의 모든 설치를 설치의 역순으로 지운다 (07 -> 06 -> 05 -> 04 -> 03 -> 02).
#
# 사용:  bash scripts/teardown/all.sh              # 확인 후 삭제
#        DRY_RUN=1 bash scripts/teardown/all.sh    # 아무것도 실행하지 않고 실행할 명령만 출력
# Windows 쪽(Ubuntu 배포판, .wslconfig)은 PowerShell 에서 scripts\teardown\00-windows-wsl.ps1 을 따로 실행한다.
# 01(systemd 설정)은 배포판 안의 /etc/wsl.conf 라서 배포판을 지우면 함께 사라진다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

cat <<MSG
다음을 설치의 역순으로 삭제합니다:
  07  tailnet 노출 서비스 (kubeflow-port-forward)
  06  Kubeflow 설치용 클론, kustomize
  05  kind 클러스터(Kubeflow 와 모든 데이터 포함), kind, kubectl, inotify 설정
  04  NVIDIA Container Toolkit, Docker 런타임 설정
  03  Docker Engine (이미지, 컨테이너, 볼륨 포함)
  02  Tailscale 연결 해제와 제거 (원격 접속이 끊깁니다)
MSG
confirm "되돌릴 수 없습니다."

export ASSUME_YES=1
[ "${DRY_RUN:-}" = 1 ] || sudo -v   # sudo 비밀번호를 한 번만 묻는다
for s in 07-1-port-forward 06-kubeflow 05-kind-cluster 04-nvidia-toolkit 03-docker 02-tailscale; do
  log "삭제 $s"
  bash "$(dirname "$0")/$s.sh"
done
log "WSL 안의 삭제 완료. Windows 쪽은 scripts\teardown\00-windows-wsl.ps1 을 실행하세요."
