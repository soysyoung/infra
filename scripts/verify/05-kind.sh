#!/usr/bin/env bash
# 05 검증: 노드 Ready -> 노드 컨테이너의 GPU -> 노드가 GPU 를 광고 -> 파드가 GPU 를 잡음
# kind 확정의 2차 관문. 실패하면 docs/decisions/0002 의 k3s 대안을 검토한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

export KUBECONFIG="$HOME/.kube/kind-mlops.yaml"
NODE=mlops-control-plane

kubectl wait --for=condition=Ready node --all --timeout=120s
docker exec "$NODE" nvidia-smi -L

# device plugin 이 Ready 가 된 뒤에도 kubelet 이 GPU 용량을 반영하기까지 몇 초 걸린다.
for _ in $(seq 30); do
  gpus=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')
  [ "${gpus:-0}" -ge 1 ] && break
  sleep 2
done
log "노드가 광고하는 GPU: ${gpus:-0}"
[ "${gpus:-0}" -ge 1 ] || die "노드가 nvidia.com/gpu 를 광고하지 않습니다 (device plugin 로그 확인)."

kubectl delete pod gpu-smoke --ignore-not-found
export CUDA_TEST_IMAGE
envsubst '${CUDA_TEST_IMAGE}' < "$ROOT/k8s/gpu-test.yaml" | kubectl apply -f -
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/gpu-smoke --timeout=180s
kubectl logs gpu-smoke
kubectl delete pod gpu-smoke

log "OK: kind 노드 안의 파드에서 GPU 확인"
