#!/usr/bin/env bash
# 09-4. OpenSearch Dashboards 를 tailnet 에 HTTPS 로 열거나(private), 인터넷에 공개하거나(public), 닫는다(off): tailscale serve, funnel, 포트 8443
#
# 왜: 핸드폰 등 tailnet 기기에서 Dashboards 를 보고, 필요할 때만 tailnet 밖의 사람에게 보이려고. 근거는 docs/decisions/0019.
# 사용:
#   bash scripts/09-4-dashboards-tailscale.sh private   # tailnet 안에서만 https://<기기>.<tailnet>.ts.net:8443
#   bash scripts/09-4-dashboards-tailscale.sh public    # 인터넷에 공개 (확인 입력 'yes' 필요)
#   bash scripts/09-4-dashboards-tailscale.sh off       # 공개를 풀고 8443 을 닫는다
#   bash scripts/09-4-dashboards-tailscale.sh status
# 원리 (Tailscale 문서):
#   - Kubeflow 가 쓰는 443 과 겹치지 않게 8443 을 쓴다. Funnel 은 포트 443, 8443, 10000 만 쓴다.
#   - 같은 포트에서 serve 와 funnel 은 함께 쓸 수 없고, 마지막에 설정한 쪽이 이긴다. 마지막이 serve 면 완전히 비공개, funnel 이면 완전히 공개다.
#   - 그래서 off 는 먼저 serve 로 비공개로 돌린 뒤 8443 항목을 지운다. 끄는 명령은 켤 때 쓴 명령 끝에 off 를 붙인다.
#   - Funnel 은 대역폭 제한이 있고 (바꿀 수 없음), 인증서를 자주 새로 받으면 Let's Encrypt 속도 제한에 걸린다. 켜고 끄기를 반복하지 않는다.
#
# 주의: public 으로 공개되는 것은 Dashboards 로그인 화면이다. admin 로그인도 같은 주소에서 시도할 수 있으므로
#   public 은 .env 의 OPENSEARCH_ADMIN_PASSWORD 가 12자 이상일 때만 진행한다. 외부 사람에게는 읽기 전용 guest-ro 계정만 알려 준다 (09-3).
#
# 선행: 09-2 (Dashboards 와 127.0.0.1:5601 port-forward 서비스), 02 (Tailscale), 관리 콘솔에서 MagicDNS 와 HTTPS Certificates 켜기, 09-3 (public 일 때)
# 참고 (공식 문서):
#   - https://tailscale.com/docs/features/tailscale-funnel
#   - https://tailscale.com/docs/reference/tailscale-cli/serve , https://tailscale.com/docs/reference/tailscale-cli/funnel
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

PORT=8443
TARGET=http://127.0.0.1:5601
require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."

dns_name() { tailscale status --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'; }
need_dashboards() {
  curl -s -m 5 -o /dev/null "$TARGET/" || die "127.0.0.1:5601 이 응답하지 않습니다. scripts/09-2-opensearch-dashboards.sh 를 먼저 하세요 (journalctl -u opensearch-dashboards-port-forward)."
}

case "${1:-}" in
  private)
    need_dashboards
    sudo timeout 60 tailscale serve --bg --https="$PORT" "$TARGET" \
      || die "tailscale serve 실패 (시간 초과이면 관리 콘솔 DNS 페이지에서 MagicDNS 와 HTTPS Certificates 가 켜져 있는지 확인하고 다시 실행)."
    sudo tailscale serve status
    log "tailnet 안에서만 열었습니다: https://$(dns_name):$PORT  (admin 또는 게스트 계정으로 로그인). 검증: scripts/verify/09-4-dashboards-tailscale.sh"
    ;;
  public)
    need_dashboards
    pw=$(sed -n 's/^OPENSEARCH_ADMIN_PASSWORD=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r' | tail -1)
    [ "${#pw}" -ge 12 ] || die ".env 의 OPENSEARCH_ADMIN_PASSWORD 가 없거나 12자 미만입니다. 관리자 로그인도 공개되므로 먼저 바꾸세요."
    grep -q '^OPENSEARCH_GUEST_RO_USER=.' "$ROOT/.env" || die "읽기 전용 guest-ro 계정이 없습니다. scripts/09-3-opensearch-guests.sh 를 먼저 하세요."
    confirm "Dashboards 로그인 화면을 인터넷에 공개합니다. 외부 사람에게는 guest-ro 계정만 알려 주세요."
    # 처음에는 관리 콘솔 승인 주소가 출력되고 승인을 기다린다.
    sudo timeout 300 tailscale funnel --bg --https="$PORT" "$TARGET" \
      || die "tailscale funnel 실패 (승인 대기 시간 초과이면 출력된 주소를 열어 승인하고 다시 실행)."
    sudo tailscale funnel status
    log "공개했습니다: https://$(dns_name):$PORT  확인: 핸드폰의 Tailscale 을 끄고 접속. 끝나면 off 로 닫으세요."
    ;;
  off)
    sudo tailscale serve --bg --https="$PORT" "$TARGET"   # 먼저 비공개로 돌린다 (문서: 마지막이 serve 면 완전히 비공개)
    sudo tailscale serve --https="$PORT" "$TARGET" off
    sudo tailscale serve status
    log "닫았습니다. 위 목록에 8443 항목과 Funnel 표시가 없어야 합니다 (443 의 Kubeflow 는 그대로)."
    ;;
  status)
    sudo tailscale serve status
    sudo tailscale funnel status
    ;;
  *) die "사용법: bash scripts/09-4-dashboards-tailscale.sh private|public|off|status" ;;
esac
