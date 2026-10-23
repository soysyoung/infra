#!/usr/bin/env bash
# 삭제 03. Docker Engine 제거 (이미지, 컨테이너, 볼륨 포함)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

if ! dpkg -s docker-ce >/dev/null 2>&1; then
  log "Docker 가 설치되어 있지 않아 건너뜁니다."; exit 0
fi
confirm "Docker 를 제거합니다. 모든 이미지, 컨테이너, 볼륨(/var/lib/docker, /var/lib/containerd)이 삭제됩니다."

run sudo systemctl disable --now docker.service docker.socket containerd.service
run sudo apt-mark unhold docker-ce docker-ce-cli
run sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
run sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
run sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc
# docker 그룹 자체는 남기고 현재 사용자만 뺀다.
run sudo gpasswd -d "$USER" docker || true
log "완료"
