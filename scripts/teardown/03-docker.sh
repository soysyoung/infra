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
# docker-ce-rootless-extras 는 docker-ce 가 추천 패키지로 함께 설치한다.
run sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
run sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
# 03-docker.sh 는 공식 문서와 같은 docker.sources 를 만든다. 예전 버전이 만든 docker.list 가 남아 있을 수 있어 둘 다 지운다.
run sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
# 브리지 인터페이스는 데몬을 지워도 WSL 을 재시작하기 전까지 커널에 남는다.
run sudo ip link delete docker0 || true
# docker 그룹 자체는 남기고 현재 사용자만 뺀다.
run sudo gpasswd -d "$USER" docker || true
log "완료"
