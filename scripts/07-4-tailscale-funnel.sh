#!/usr/bin/env bash
# 07-4. Kubeflow 를 tailnet 밖(인터넷)에 연다 / 닫는다: tailscale funnel
#
# 왜: Tailscale 계정이 없는 사람이 https://<기기>.<tailnet>.ts.net 으로 접속하게 하려고.
# 사용:
#   bash scripts/07-4-tailscale-funnel.sh on       # 인터넷에 공개 (확인 입력 'yes' 필요)
#   bash scripts/07-4-tailscale-funnel.sh off      # 공개를 풀고 tailnet 안에서만 HTTPS (07-3 상태로 복귀)
#   bash scripts/07-4-tailscale-funnel.sh status
# 원리 (Tailscale 문서):
#   - 같은 포트(443)에서 serve 와 funnel 은 함께 쓸 수 없고, 마지막에 설정한 쪽이 이긴다.
#     마지막이 serve 면 그 포트는 완전히 비공개이고, funnel 이면 완전히 공개다.
#   - 그래서 off 는 07-3 과 같은 serve 명령을 다시 적용한다.
#   - Funnel 은 포트 443, 8443, 10000 만 쓰고 대역폭 제한이 있다 (바꿀 수 없음).
#   - 처음 켜면 관리 콘솔에서 승인하라는 주소가 나온다. 승인하면 정책 파일에 funnel 노드 속성이 추가된다.
#
# 주의: 공개되는 것은 Kubeflow 로그인 화면 전체다. 관리자 계정(user@example.com)의 로그인도 같은 주소에서 시도할 수 있다.
#   그래서 on 은 .env 의 KUBEFLOW_PASSWORD 가 12자 이상일 때만 진행한다. 공유가 끝나면 off 로 닫는다.
#
# 선행: 07-1, 07-3 (serve 가 켜져 있어야 off 가 의미 있다), 06-2 (공유용 계정, 선택)
# 참고 (공식 문서):
#   - Funnel: https://tailscale.com/docs/features/tailscale-funnel
#   - 명령: https://tailscale.com/docs/reference/tailscale-cli/funnel
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

TARGET=http://127.0.0.1:8080
require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."

case "${1:-}" in
  on)
    curl -s -m 5 -o /dev/null "$TARGET/" || die "127.0.0.1:8080 이 응답하지 않습니다. 07-1-port-forward.sh 를 먼저 하세요."
    pw=$(sed -n 's/^KUBEFLOW_PASSWORD=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r')
    [ "${#pw}" -ge 12 ] || die ".env 의 KUBEFLOW_PASSWORD 가 없거나 12자 미만입니다. 관리자 로그인도 공개되므로 먼저 바꾸고 06 을 다시 실행하세요."
    confirm "Kubeflow 로그인 화면을 인터넷에 공개합니다."
    # 처음에는 관리 콘솔 승인 주소가 출력되고 승인을 기다린다.
    sudo timeout 300 tailscale funnel --bg --https=443 "$TARGET" \
      || die "tailscale funnel 실패 (승인 대기 시간 초과이면 출력된 주소를 열어 승인하고 다시 실행)."
    sudo tailscale funnel status
    log "공개했습니다. 확인: 핸드폰의 Tailscale 을 끄고(또는 모바일 데이터로) 위 https:// 주소에 접속. 끝나면 off 로 닫으세요."
    ;;
  off)
    sudo tailscale serve --bg --https=443 "$TARGET"
    sudo tailscale serve status
    log "공개를 풀었습니다. 위 목록에 Funnel 표시가 없어야 합니다. tailnet 안에서는 HTTPS 로 접속됩니다."
    ;;
  status)
    sudo tailscale funnel status
    ;;
  *) die "사용법: bash scripts/07-4-tailscale-funnel.sh on|off|status" ;;
esac
