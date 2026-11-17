#!/usr/bin/env bash
# 04. NVIDIA Container Toolkit 설치 및 Docker 연동
#
# 왜: 컨테이너(와 kind 노드 안의 파드)가 GPU 를 쓰려면 필요하다.
# 하는 일: apt 저장소 등록 -> versions.env 의 버전으로 설치 -> Docker 의 기본 런타임을 nvidia 로 설정 -> Docker 재시작
# 주의: WSL 안에는 NVIDIA 드라이버를 설치하지 않는다. Windows 쪽 드라이버를 /usr/lib/wsl 로 공유받는다.
#
# 선행: 03-docker.sh, Windows 에 최신 NVIDIA 드라이버
#
# 참고 (공식 문서):
#   - 설치: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
#   - WSL2 의 CUDA: https://docs.nvidia.com/cuda/wsl-user-guide/index.html
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd docker "03-docker.sh 를 먼저 하세요."
# WSL 의 nvidia-smi 는 PATH 에 없을 수 있어 경로를 직접 확인한다.
[ -x /usr/lib/wsl/lib/nvidia-smi ] || die "WSL 에서 GPU 가 보이지 않습니다. Windows NVIDIA 드라이버를 확인하세요."

V="$NVIDIA_TOOLKIT_VERSION-1"

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
sudo apt-get update

sudo apt-mark unhold nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
sudo apt-get install -y --allow-downgrades \
  "nvidia-container-toolkit=$V" "nvidia-container-toolkit-base=$V" \
  "libnvidia-container-tools=$V" "libnvidia-container1=$V"
sudo apt-mark hold nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1

# kind 노드 컨테이너가 GPU 를 받으려면 nvidia 가 기본 런타임이어야 하고, 노드에는 마커 마운트
# (/var/run/nvidia-container-devices/all) 로 장치를 알린다. NVIDIA nvkind 문서의 설정과 같다.
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled
sudo nvidia-ctk config --in-place --set accept-nvidia-visible-devices-as-volume-mounts=true
sudo systemctl restart docker

log "완료. 검증: scripts/verify/04-gpu.sh"
