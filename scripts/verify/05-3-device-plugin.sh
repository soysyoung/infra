#!/usr/bin/env bash
# 05-3 검증: device plugin 이 GPU 노드에만 뜸 -> 노드가 GPU 를 광고 -> GPU 파드가 GPU 노드에서 GPU 를 잡음
# kind 확정의 2차 관문. 실패하면 docs/decisions/0002 의 k3s 대안을 검토한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NODE=$(gpu_node)
[ -n "$NODE" ] || die "라벨 $GPU_LABEL 이 붙은 노드가 없습니다."

desired=$(kubectl -n kube-system get ds nvidia-device-plugin-daemonset -o jsonpath='{.status.desiredNumberScheduled}')
[ "$desired" -eq 1 ] || die "device plugin 이 $desired 개 노드에 배치되었습니다 (기대: GPU 노드 1개)."

# device plugin 이 Ready 가 된 뒤에도 kubelet 이 GPU 용량을 반영하기까지 몇 초 걸린다.
for _ in $(seq 30); do
  gpus=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')
  [ "${gpus:-0}" -eq "$GPU_REPLICAS" ] && break
  sleep 2
done
log "$NODE 가 광고하는 GPU: ${gpus:-0} (기대: 물리 GPU 1장 x GPU_REPLICAS=$GPU_REPLICAS)"
[ "${gpus:-0}" -eq "$GPU_REPLICAS" ] || die "광고 개수가 다릅니다 (device plugin 로그와 ConfigMap nvidia-device-plugin-config 확인)."

kubectl delete pod gpu-smoke --ignore-not-found
export CUDA_TEST_IMAGE
envsubst '${CUDA_TEST_IMAGE}' < "$ROOT/k8s/gpu-test.yaml" | kubectl apply -f -
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/gpu-smoke --timeout=180s
kubectl logs gpu-smoke
placed=$(kubectl get pod gpu-smoke -o jsonpath='{.spec.nodeName}')
kubectl delete pod gpu-smoke
[ "$placed" = "$NODE" ] || die "GPU 파드가 GPU 노드가 아닌 $placed 에 올라갔습니다."

log "OK: GPU 파드가 $placed 에서 GPU 를 잡음"
