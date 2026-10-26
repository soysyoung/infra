#!/usr/bin/env bash
# 07-3. tailnet 의 다른 기기(핸드폰 등)에 Kubeflow 를 HTTPS 로 연다: tailscale serve
#
# 왜: Kubeflow 웹앱(Jupyter, Tensorboard, Katib UI)은 Secure 쿠키를 써서 localhost 가 아닌 주소에 HTTP 로 접속하면
#     동작하지 않는다. NodePort 도 공식이 권하지 않는다 (docs/decisions/0011). 그래서 게이트웨이는 ClusterIP 로 두고,
#     tailscaled 가 HTTPS 를 종료해서 07-1 의 port-forward(127.0.0.1:8080)로 넘기게 한다.
# 하는 일: tailscale serve --bg --https=443 http://127.0.0.1:8080
#   --bg 면 재부팅이나 Tailscale 재시작 뒤에도 자동으로 다시 공유한다 (Tailscale 문서). 여러 번 실행해도 같은 설정을 덮어쓴다.
# 접속: https://<기기 이름>.<tailnet 이름>.ts.net  (주소는 아래에 출력된다)
#
# 선행: 02, 07-1, Tailscale 관리 콘솔(DNS 페이지)에서 MagicDNS 와 HTTPS Certificates 켜기
# 검증: scripts/verify/07-3-tailscale-serve.sh
# 미검증: Kubeflow 로그인이 ts.net HTTPS 주소에서 정상인지. 로그인 뒤 http 로 돌아가거나 반복되면 oauth2-proxy 의
#   FORCE_HTTPS 설정을 확인한다 (docs/decisions/0011).
#
# 참고 (공식 문서):
#   - tailscale serve: https://tailscale.com/docs/reference/tailscale-cli/serve
#   - Kubeflow 접속: https://github.com/kubeflow/community-distribution (NodePort / LoadBalancer / Ingress 절)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."
curl -s -m 5 -o /dev/null http://127.0.0.1:8080/ || die "127.0.0.1:8080 이 응답하지 않습니다. 07-1-port-forward.sh 를 먼저 하세요."

# HTTPS 인증서가 켜져 있지 않으면 tailscale 이 켜는 방법을 안내하고 기다리므로 시간을 제한한다.
sudo timeout 60 tailscale serve --bg --https=443 http://127.0.0.1:8080 \
  || die "tailscale serve 실패 (시간 초과이면 관리 콘솔 DNS 페이지에서 MagicDNS 와 HTTPS Certificates 가 켜져 있는지 확인하고 다시 실행)."

sudo tailscale serve status
log "완료. 위 https:// 주소로 접속하세요.  검증: scripts/verify/07-3-tailscale-serve.sh"
