# 0019. Dashboards 노출: tailscale serve(기본)와 funnel(필요할 때만), 포트 8443

- 상태: `private`(tailnet 안), `public`(funnel), `off` 적용 (2026-10-30). 이름 변경 뒤 옛 이름 설정이 남는 문제는 troubleshooting 30번

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
- 사용자 보고: Tailscale 관리 콘솔에서 기기 이름을 바꾼 뒤 `09-4 public` 을 다시 실행했고 접속 시험이 된다. 이름을 바꾸면 주소가 새 이름으로 바뀌고, 스크립트를 다시 실행해 맞췄다 (스크립트가 이름을 매번 읽는다). 이름을 바꾼 뒤 `private` 이 저절로 새 이름으로 이어졌는지는 확인하지 못했다.
- 사용자 실행 `09-4 off`: 새 이름의 8443 항목이 사라졌다 (`off` 단독 동작 확인). 그런데 `serve status` 에 **옛 이름**의 443(Kubeflow)과 8443 항목이 `Funnel on` 으로 남아 있었다. serve, funnel 설정은 호스트 이름을 키로 저장돼 이름 변경 전에 만든 항목을 새 이름의 스크립트가 못 지운다 ([troubleshooting.md](../troubleshooting.md) 30번). `sudo tailscale serve reset` 후 `07-3`, `09-4 private` 를 다시 실행하자 새 이름의 443(8080)과 8443(5601) 둘 다 `(tailnet only)` 로 보였고 `verify/07-3` 이 `==> OK` 였다.
- `verify/09-4` 통과 (이름 변경과 `reset` 뒤): 8443 항목 있음, `https://<기기>.<tailnet>.ts.net:8443/` 가 302 로 `/app/login` (https 와 8443 유지)으로 응답, `==> OK` ([verify/README.md](../../scripts/verify/README.md)). 이때 443 검사가 `:443` 을 찾아 거짓 경고를 냈고 `https://<이름> (` 을 찾도록 고쳤다 (고친 뒤 재실행에서 `443(Kubeflow) 항목도 그대로 있음` 확인).
- 한계: 이름을 바꾸는 순간 옛 이름의 Funnel 항목이 인터넷에 노출되는지는 모른다. `reset` 전에 이 PC 에서 요청한 결과는 새 이름과 같은 TLS 실패였다. 이름을 바꿀 때는 먼저 `off` 를 하고 바꾸는 것이 안전하다 (추정).
- 미확인: 접속 시험을 한 곳(Tailscale 을 끈 기기인지)과 로그인에 쓴 계정, `public` 이 이름 변경 뒤 정말 외부에서 열렸는지, 대역폭 제한, guest-ro 로그인 후 화면. 이 시험에서 guest-rw 는 `kibana_user` 가 없어 화면 일부가 제한될 수 있다 ([ADR 0018](0018-opensearch-guest-accounts.md) 의 미해소 항목).
