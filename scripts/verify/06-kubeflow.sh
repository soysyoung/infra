#!/usr/bin/env bash
# 06 검증: 핵심 네임스페이스의 Deployment 가 Available -> 로그인 화면이 응답
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

for ns in cert-manager istio-system auth oauth2-proxy knative-serving kubeflow-system kubeflow; do
  # kubeflow-system 처럼 Deployment 가 없는 네임스페이스에는 kubectl wait 가 실패하므로 건너뛴다.
  [ -n "$(kubectl -n "$ns" get deploy -o name)" ] || continue
  kubectl wait --for=condition=Available deployment --all -n "$ns" --timeout=60s
done
kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed" {bad++; print} END{exit bad>0}' \
  || die "Running/Completed 가 아닌 파드가 있습니다."

# 로그인 전 '/' 는 oauth2-proxy 의 Sign In 페이지와 함께 403 (ext_authz_denied) 이 정상이다.
# 로그인 흐름이 이어지는지는 /oauth2/start 가 Dex 로 리다이렉트하는지로 확인한다.
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
pf=$!; trap 'kill $pf 2>/dev/null' EXIT
for _ in $(seq 15); do
  redirect=$(curl -s -o /dev/null -w '%{redirect_url}' http://localhost:8080/oauth2/start || true)
  case "$redirect" in */dex/auth*) break ;; esac
  sleep 2
done
log "/oauth2/start 의 리다이렉트: ${redirect:-없음}"
case "$redirect" in */dex/auth*) ;; *) die "로그인 흐름(/oauth2/start -> /dex/auth)이 동작하지 않습니다." ;; esac

log "OK: Kubeflow 구성요소가 Available 이고 로그인 흐름(oauth2-proxy -> Dex)이 동작함"
