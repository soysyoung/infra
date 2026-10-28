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

kubectl apply -f "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$DEVICE_PLUGIN_VERSION/deployments/static/nvidia-device-plugin.yml"
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type merge \
  -p "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"${GPU_LABEL%%=*}\":\"${GPU_LABEL#*=}\"}}}}}"

# time-slicing: static 매니페스트에는 설정 수단이 없어서 ConfigMap 을 만들어 CONFIG_FILE 로 읽게 한다.
# 컨테이너와 볼륨은 name 으로 병합되므로 기존 hostPath 마운트는 유지된다. 파드 템플릿이 바뀌어 DaemonSet 이 다시 뜬다.
export GPU_REPLICAS
envsubst '${GPU_REPLICAS}' < "$ROOT/k8s/device-plugin-config.yaml" | kubectl apply -f -
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type strategic -p '
spec:
  template:
    spec:
      containers:
      - name: nvidia-device-plugin-ctr
        env:
        - {name: CONFIG_FILE, value: /config/config.yaml}
        volumeMounts:
        - {name: plugin-config, mountPath: /config}
      volumes:
      - name: plugin-config
        configMap: {name: nvidia-device-plugin-config}'
# ConfigMap 만 바뀌고 템플릿은 그대로인 재실행(개수 변경)에서는 파드가 설정을 다시 읽지 않으므로 재시작한다.
kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset
kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset --timeout=180s

log "GPU 1장을 ${GPU_REPLICAS}개로 광고합니다 (time-slicing, VRAM 은 격리되지 않음)."

log "완료. 검증: scripts/verify/05-3-device-plugin.sh"
