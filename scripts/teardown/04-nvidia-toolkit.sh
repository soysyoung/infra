#!/usr/bin/env bash
# 삭제 04. NVIDIA Container Toolkit 제거와 Docker 런타임 설정 되돌리기
#
# 순서: daemon.json 을 03 이 만든 상태로 먼저 되돌리고 Docker 를 재시작한 뒤 패키지를 지운다.
# 거꾸로 하면 Docker 가 없어진 nvidia 런타임을 찾다가 시작에 실패한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

if ! dpkg -s nvidia-container-toolkit >/dev/null 2>&1; then
  log "NVIDIA Container Toolkit 이 설치되어 있지 않아 건너뜁니다."; exit 0
fi
confirm "NVIDIA Container Toolkit 을 제거하고 Docker 기본 런타임을 되돌립니다."

if type -P docker >/dev/null; then
  run sudo sh -c "echo '{\"features\": {\"containerd-snapshotter\": false}}' > /etc/docker/daemon.json"
  run sudo systemctl restart docker
fi
pkgs="nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1"
run sudo apt-mark unhold $pkgs
run sudo apt-get purge -y $pkgs
run sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
log "완료"
