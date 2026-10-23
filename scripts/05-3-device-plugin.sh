#!/usr/bin/env bash
# 05-3. NVIDIA device plugin 설치 (GPU 노드에만)
#
# 왜: 노드가 nvidia.com/gpu 를 Kubernetes 에 광고해야 파드가 GPU 를 요청할 수 있다.
# 하는 일: 공식 static 매니페스트를 적용하고 GPU 라벨 노드로 제한한다.
#   매니페스트에는 nodeSelector 가 없어서 그대로 두면 CPU 노드에도 떠서 NVML 을 못 찾고 계속 죽는다.
#
# 선행: 05-2-gpu-node.sh
# 검증: scripts/verify/05-3-device-plugin.sh
#
# 참고 (공식 문서):
#   - device plugin: https://github.com/NVIDIA/k8s-device-plugin
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

export KUBECONFIG="$KUBECONFIG_FILE"

kubectl apply -f "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$DEVICE_PLUGIN_VERSION/deployments/static/nvidia-device-plugin.yml"
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type merge \
  -p "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"${GPU_LABEL%%=*}\":\"${GPU_LABEL#*=}\"}}}}}"
kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset --timeout=180s

log "완료. 검증: scripts/verify/05-3-device-plugin.sh"
