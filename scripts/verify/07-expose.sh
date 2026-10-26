#!/usr/bin/env bash
# 07 검증: tailnet 주소로 Kubeflow 로그인 흐름이 응답하는가
# port-forward 방식(포트 8080, 07-expose.sh)과 NodePort 방식(포트 30080, kind-config 의 extraPortMappings)을 각각 확인하고, 하나라도 되면 통과한다.
# 비교는 docs/decisions/0009.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

TAILNET_IP=$(tailscale ip -4)
ok=0
for entry in "port-forward:8080" "NodePort:30080"; do
  m=${entry%%:*}; port=${entry##*:}
  redirect=$(curl -s -m 5 -o /dev/null -w '%{redirect_url}' "http://$TAILNET_IP:$port/oauth2/start" || true)
  case "$redirect" in
    */dex/auth*) log "$m 방식 ($TAILNET_IP:$port): OK  ($redirect)"; ok=1 ;;
    *)           log "$m 방식 ($TAILNET_IP:$port): 응답 없음 또는 로그인 흐름이 아님" ;;
  esac
done
[ "$ok" = 1 ] || die "tailnet 주소로 Kubeflow 에 접속할 수 없습니다 (07-expose.sh 실행 여부, 클러스터가 extraPortMappings 로 만들어졌는지 확인)."

log "OK: tailnet 주소로 Kubeflow 로그인 흐름(oauth2-proxy -> Dex)이 동작함"
