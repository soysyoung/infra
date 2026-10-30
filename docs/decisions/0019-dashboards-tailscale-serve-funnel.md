# 0019. Dashboards 노출: tailscale serve(기본)와 funnel(필요할 때만), 포트 8443

- 상태: `private`(tailnet 안) 적용 (2026-10-30). `public`(funnel)과 `off` 는 **미적용**

## 상황
Dashboards([ADR 0017](0017-opensearch-dashboards.md))는 이 PC 의 `http://localhost:5601` 로만 열린다. 핸드폰 등 tailnet 기기에서 보고, 필요하면 tailnet 밖의 사람에게도 보여 주고 싶다. Kubeflow 는 이미 443 으로 serve(07-3)와 funnel(07-4)을 쓴다 ([ADR 0011](0011-no-nodeport-https-via-tailscale-serve.md)).

## 확인한 것 (2026-10-30, Tailscale 공식 문서)
출처: [Tailscale Funnel](https://tailscale.com/docs/features/tailscale-funnel), [tailscale funnel](https://tailscale.com/docs/reference/tailscale-cli/funnel), [tailscale serve](https://tailscale.com/docs/reference/tailscale-cli/serve). 문서는 캐시된 사본으로 읽었다 (funnel 페이지 2026-10-28, serve 페이지 2026-10-30).
- Funnel 은 포트 **443, 8443, 10000** 만 쓴다. TLS 만 되고, 대역폭 제한이 있으며(바꿀 수 없음), 인증서를 자주 새로 받으면 Let's Encrypt 속도 제한에 걸린다.
- **같은 포트에서 serve 와 funnel 을 함께 쓸 수 없다.** 마지막에 설정한 쪽이 이긴다: serve 면 완전히 비공개, funnel 이면 완전히 공개.
- 명령은 `tailscale serve|funnel --bg --https=<포트> <대상>`, 끄는 것은 켤 때 쓴 명령 끝에 `off` (대상은 생략할 수 있지만 원래 플래그는 필요).
- Funnel 을 처음 켜면 관리 콘솔 승인과 정책 파일의 노드 속성이 필요하다 (07-4 와 같다).

## 결정
- Dashboards 는 **8443** 에 올린다. 443 은 Kubeflow 가 쓰므로 겹치지 않는다. 주소는 `https://<기기>.<tailnet>.ts.net:8443`. 대상은 `09-2` 의 port-forward 서비스가 여는 `http://127.0.0.1:5601` 이다.
- 기본은 **tailnet 안에서만**(`private`, serve). 인터넷 공개(`public`, funnel)는 필요할 때만 켜고 끝나면 `off` 로 닫는다. 07-3, 07-4 와 같은 규칙이다.
- `public` 의 안전장치: `.env` 의 admin 비밀번호가 12자 이상이어야 하고, 읽기 전용 `guest-ro`(09-3)가 있어야 하며, 확인 입력('yes')을 받는다. 외부 사람에게는 `guest-ro` 만 알려 준다 ([ADR 0018](0018-opensearch-guest-accounts.md)). 공개되는 것은 로그인 화면 전체라 admin 로그인도 같은 주소에서 시도할 수 있다는 점은 그대로다.
- `off` 는 먼저 serve 로 비공개로 돌린 뒤 8443 항목을 지운다 (문서의 "마지막이 serve 면 비공개" 규칙에 기댄다. `off` 단독의 동작은 시험 전이다).
- 스크립트는 `serve reset` 을 쓰지 않는다. 443 의 Kubeflow 설정을 건드리지 않는다.

## 미검증 (적용 전)
- `09-4 private` 와 `verify/09-4` 가 실제로 통과하는지. 특히 8443 의 `serve` 가 443 과 함께 동작하는지, Dashboards 가 프록시 뒤에서 리다이렉트를 `https://...:8443` 으로 유지하는지.
- `serve` 의 `--https=8443` 이 허용되는지 (문서에서 funnel 의 포트 목록은 확인했고 serve 쪽 목록은 문구로 확인하지 못했다).
- Dashboards 로그인 쿠키가 HTTPS, 포트 8443 에서 정상 동작하는지 (브라우저로 확인).
- `public` 의 관리 콘솔 승인 절차, 외부 접속, `off` 후 실제로 닫히는지. Kubeflow 퍼널 시험(todo 1번)과 같은 방식으로 한다. 켜고 끄기를 반복하지 않는다.
- 대역폭 제한이 Dashboards 사용에 충분한지.

## 적용 결과 (2026-10-30)
- 사용자 보고: `09-4 private` 를 실행했고 `https://<기기>.<tailnet>.ts.net:8443` 로 접속된다. guest-rw 로 로그인도 된다. `serve` 의 `--https=8443` 이 받아들여졌고, 8443 프록시 뒤에서 로그인과 쿠키가 동작한다.
- 미확인: `verify/09-4` 의 출력, Kubeflow(443)와 함께 동작하는지 (접속 시험은 8443 만), `public`(funnel)과 `off`, 대역폭 제한, guest-ro 로그인 후 화면. 이 시험에서 guest-rw 는 `kibana_user` 가 없어 화면 일부가 제한될 수 있다 ([ADR 0018](0018-opensearch-guest-accounts.md) 의 미해소 항목).
