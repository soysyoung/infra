#!/usr/bin/env bash
# 03. Docker Engine 설치 (Docker 공식 apt 저장소)
#
# 왜: kind 가 Docker 컨테이너를 노드로 쓴다. 이미지 빌드도 같은 Docker 로 한다 (런타임 하나).
# 하는 일: apt 저장소 등록 -> versions.env 의 DOCKER_VERSION 으로 고정 설치 -> 자동 업그레이드 방지(hold)
#   -> 현재 사용자를 docker 그룹에 추가
#
# 선행: 01-wsl-systemd.sh 후 WSL 재시작
#
# 참고 (공식 문서):
#   - Ubuntu 설치: https://docs.docker.com/engine/install/ubuntu/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_systemd

want="${DOCKER_VERSION#5:}"; want="${want%%-*}"   # 5:29.9.0-1~ubuntu... -> 29.9.0
if [ -n "$want" ] && command -v docker >/dev/null && docker --version | grep -q "version $want,"; then
  log "Docker 가 이미 설치되어 있습니다: $(docker --version)"
  exit 0
fi

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update

if [ -z "$DOCKER_VERSION" ]; then
  echo "설치 가능한 Docker 29.x 버전:" >&2
  apt-cache madison docker-ce | awk '{print $3}' | grep '^5:29\.' | head -10 >&2
  die "versions.env 의 DOCKER_VERSION 을 정하고 다시 실행하세요."
fi

sudo apt-get install -y \
  "docker-ce=$DOCKER_VERSION" "docker-ce-cli=$DOCKER_VERSION" \
  containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt-mark hold docker-ce docker-ce-cli

# Docker 29 는 containerd 이미지 스토어가 기본이라 'kind load docker-image' 가 실패할 수 있다.
# (kubernetes-sigs/kind#3795) 그래서 끈다. 04 의 nvidia-ctk 는 이 파일에 설정을 병합한다.
if [ -s /etc/docker/daemon.json ]; then
  die "/etc/docker/daemon.json 이 이미 있습니다. features.containerd-snapshotter=false 를 직접 병합하세요."
fi
sudo mkdir -p /etc/docker
echo '{"features": {"containerd-snapshotter": false}}' | sudo tee /etc/docker/daemon.json >/dev/null

sudo systemctl enable docker
sudo systemctl restart docker
sudo usermod -aG docker "$USER"

log "완료: $(docker --version)"
echo "docker 그룹 적용을 위해 WSL 터미널을 새로 여세요 (또는 'newgrp docker')."
