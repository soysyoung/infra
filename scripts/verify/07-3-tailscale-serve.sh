#!/usr/bin/env bash
# 07-3 검증: tailnet 의 HTTPS 주소 (https://<기기>.<tailnet>.ts.net) 로 Kubeflow 로그인 흐름이 응답하고,
# 로그인 리다이렉트가 HTTPS 를 유지하는가 (http 로 떨어지면 Secure 쿠키가 거부된다)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

name=$(tailscale status --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$name" ] || die "이 기기의 tailnet 이름을 알 수 없습니다 (tailscale status)."

# WSL 의 DNS 설정에 상관없이 이 기기의 tailnet 주소로 직접 연결한다. 인증서 검증은 이름으로 한다.
r=$(curl -s -m 10 --resolve "$name:443:$(tailscale ip -4)" -o /dev/null -w '%{redirect_url}' "https://$name/oauth2/start" || true)
log "https://$name/oauth2/start 의 리다이렉트: ${r:-없음}"
case "$r" in
  https://*/dex/auth*) ;;
  http://*/dex/auth*)  die "리다이렉트가 http 로 떨어집니다. oauth2-proxy 가 HTTPS 를 인식하지 못하므로 FORCE_HTTPS 설정을 확인하세요 (docs/decisions/0011)." ;;
  *)                   die "HTTPS 로그인 흐름이 동작하지 않습니다 (07-3-tailscale-serve.sh 실행 여부, 관리 콘솔의 HTTPS Certificates 확인)." ;;
esac

log "OK: https://$name 로 Kubeflow 로그인 흐름이 HTTPS 를 유지하며 동작함"
