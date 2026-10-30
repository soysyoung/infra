#!/usr/bin/env bash
# 09-4 검증: tailnet 의 HTTPS 주소(https://<기기>.<tailnet>.ts.net:8443)로 Dashboards 가 응답하고,
# 리다이렉트가 HTTPS 와 8443 을 유지하며, Kubeflow 의 443 설정이 그대로인가. 공개(funnel) 여부는 출력만 한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

PORT=8443
name=$(tailscale status --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$name" ] || die "이 기기의 tailnet 이름을 알 수 없습니다 (tailscale status)."

status=$(sudo tailscale serve status 2>&1 || true)
echo "$status" | grep -q ":$PORT" || die "serve 목록에 $PORT 가 없습니다 (scripts/09-4-dashboards-tailscale.sh private 실행 여부). 출력: $status"
log "serve 목록에 $PORT 있음"

# 07-3 의 검증과 같은 방식: WSL 의 DNS 에 상관없이 이 기기의 tailnet 주소로 직접 연결하고 인증서는 이름으로 검증한다.
# 새 포트의 첫 HTTPS 요청은 인증서 준비로 잠시 실패할 수 있어서 최대 60초 재시도한다.
code=000; loc=""
for i in $(seq 1 12); do
  out=$(curl -s -m 10 --resolve "$name:$PORT:$(tailscale ip -4)" -o /dev/null -w '%{http_code} %{redirect_url}' "https://$name:$PORT/" || true)
  code=${out%% *}; loc=${out#* }
  case "$code" in 200|302) break;; esac
  [ "$i" = 1 ] && log "응답이 없어 최대 60초 재시도합니다 (인증서 준비 중일 수 있음)"
  sleep 5
done
log "https://$name:$PORT/ 응답: $code ${loc:+-> $loc}"
case "$code" in 200|302) ;; *) die "Dashboards 가 HTTPS 로 응답하지 않습니다 (09-4 private 실행 여부, 관리 콘솔의 HTTPS Certificates, journalctl -u opensearch-dashboards-port-forward 확인).";; esac
case "$loc" in http://*) die "리다이렉트가 http 로 떨어집니다: $loc";; esac

echo "$status" | grep -q ":443" && log "443(Kubeflow) 항목도 그대로 있음" || log "주의: serve 목록에 443 항목이 없습니다 (Kubeflow 를 07-3 으로 열지 않았다면 정상)."
log "Funnel 상태 (공개 중이면 아래에 8443 이 나옵니다):"; sudo tailscale funnel status 2>&1 || true

log "OK: https://$name:$PORT 로 Dashboards 가 HTTPS 로 응답함 (로그인은 브라우저로 확인)"
