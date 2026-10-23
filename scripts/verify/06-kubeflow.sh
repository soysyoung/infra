#!/usr/bin/env bash
# 06 검증: 핵심 네임스페이스의 Deployment 가 Available -> 로그인 화면이 응답
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

export KUBECONFIG="$KUBECONFIG_FILE"

for ns in cert-manager istio-system auth oauth2-proxy knative-serving kubeflow-system kubeflow; do
  kubectl wait --for=condition=Available deployment --all -n "$ns" --timeout=60s
done
kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed" {bad++; print} END{exit bad>0}' \
  || die "Running/Completed 가 아닌 파드가 있습니다."

kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
pf=$!; trap 'kill $pf 2>/dev/null' EXIT
for _ in $(seq 15); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ || true)
  case "$code" in 200|301|302|303|307) break ;; esac
  sleep 2
done
log "Istio 게이트웨이 응답: HTTP $code"
case "$code" in 200|301|302|303|307) ;; *) die "게이트웨이가 응답하지 않습니다 (HTTP $code)." ;; esac

log "OK: Kubeflow 구성요소가 Available 이고 게이트웨이가 응답함"
