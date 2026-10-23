#!/usr/bin/env bash
# 05-2 검증: GPU 노드 컨테이너에서 GPU 가 보이고 containerd 가 nvidia 런타임으로 설정되었는가
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

export KUBECONFIG="$KUBECONFIG_FILE"
NODE=$(gpu_node)
[ -n "$NODE" ] || die "라벨 $GPU_LABEL 이 붙은 노드가 없습니다."

docker exec "$NODE" nvidia-smi -L
docker exec "$NODE" test -f /etc/containerd/conf.d/99-nvidia.toml || die "$NODE 의 containerd 가 nvidia 런타임으로 설정되지 않았습니다 (05-2-gpu-node.sh)."

log "OK: $NODE 에서 GPU 확인, containerd nvidia 런타임 설정됨"
