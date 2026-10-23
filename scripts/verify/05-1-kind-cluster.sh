#!/usr/bin/env bash
# 05-1 검증: 노드 4개 Ready -> GPU 노드 라벨/taint -> 일반 파드가 GPU 노드를 피함
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

export KUBECONFIG="$KUBECONFIG_FILE"
EXPECTED_NODES=4

kubectl wait --for=condition=Ready node --all --timeout=120s
kubectl get nodes -L nvidia.com/gpu.present

n=$(kubectl get nodes --no-headers | wc -l)
[ "$n" -eq "$EXPECTED_NODES" ] || die "노드가 $n 개입니다 (기대: $EXPECTED_NODES)."

NODE=$(gpu_node)
[ -n "$NODE" ] || die "라벨 $GPU_LABEL 이 붙은 노드가 없습니다."
kubectl get node "$NODE" -o jsonpath='{.spec.taints[*].key}' | grep -q nvidia.com/gpu || die "$NODE 에 nvidia.com/gpu taint 가 없습니다."

# GPU 를 요청하지 않는 파드는 taint 때문에 GPU 노드로 가지 않아야 한다.
kubectl delete pod cpu-smoke --ignore-not-found
kubectl run cpu-smoke --image=busybox:1.37 --restart=Never --command -- hostname
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/cpu-smoke --timeout=180s
placed=$(kubectl get pod cpu-smoke -o jsonpath='{.spec.nodeName}')
kubectl delete pod cpu-smoke
[ "$placed" != "$NODE" ] || die "일반 파드가 GPU 노드($NODE)에 올라갔습니다."

log "OK: 노드 $n 개 Ready, GPU 노드 $NODE (taint 적용), 일반 파드는 $placed 에 배치됨"
