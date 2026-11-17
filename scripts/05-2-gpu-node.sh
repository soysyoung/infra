#!/usr/bin/env bash
# 05-2. GPU 노드 설정: 노드 컨테이너 안에 NVIDIA toolkit 설치 + containerd 를 nvidia 런타임으로
#
# 왜: 호스트 Docker 의 nvidia 런타임은 노드 컨테이너까지만 GPU 를 넣는다. 노드 안의 containerd 가
#     파드에 GPU 라이브러리를 넣으려면 노드 안에도 toolkit 이 필요하다 (nvkind 의 노드 후처리와 같다).
#     이 설정이 없으면 device plugin 이 NVML 을 못 찾고 죽는다.
# 하는 일: 라벨로 GPU 노드를 찾아 그 노드에만 toolkit 설치, containerd 설정, 재시작. 이미 했으면 건너뜀.
#
# 선행: 05-1-kind-cluster.sh
# 다음: 05-3-device-plugin.sh
# 검증: scripts/verify/05-2-gpu-node.sh
#
# 참고 (공식 문서):
#   - GPU 설정(nvkind): https://github.com/NVIDIA/nvkind
#   - toolkit 설치: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NODE=$(gpu_node)
[ -n "$NODE" ] || die "라벨 $GPU_LABEL 이 붙은 노드가 없습니다. 05-1-kind-cluster.sh 를 먼저 하세요."

if docker exec "$NODE" test -f /etc/containerd/conf.d/99-nvidia.toml; then
  log "$NODE 는 이미 설정되어 있습니다."
else
  docker exec -i -e V="$NVIDIA_TOOLKIT_VERSION-1" -e DEBIAN_FRONTEND=noninteractive "$NODE" bash -s <<'EOS'
set -e
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg >/dev/null
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -qq
apt-get install -y -qq "nvidia-container-toolkit=$V" "nvidia-container-toolkit-base=$V" \
  "libnvidia-container-tools=$V" "libnvidia-container1=$V" >/dev/null
nvidia-ctk runtime configure --runtime=containerd --config-source=file --set-as-default --cdi.enabled
systemctl restart containerd
EOS
  kubectl wait --for=condition=Ready "node/$NODE" --timeout=120s
fi

log "완료. 다음: scripts/05-3-device-plugin.sh"
