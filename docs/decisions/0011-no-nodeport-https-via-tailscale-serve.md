# 0011. Kubeflow 접속: port-forward(localhost) 와 tailscale serve(HTTPS). NodePort 는 쓰지 않는다

- 상태: 채택 (2026-10-26). **서버 쪽 HTTPS 경로는 시험 통과**: `07-1`, `07-3` 의 검증이 통과했고 로그인 리다이렉트가 `https://` 를 유지했다. **핸드폰 브라우저의 로그인과 Notebook 생성, 재부팅 후 `tailscale serve` 재개는 미시험.** NodePort 를 쓰지 않는 이유 중 공식 문서 인용과 서버 쪽 실측은 확인했고, 브라우저 동작은 추정이다.
- [ADR 0009](0009-tailnet-exposure-port-forward-vs-nodeport.md) 의 비교와 시험 기록을 이어받는다. 0009 가 NodePort 를 후보로 둔 결정과 `tailscale serve` 를 쓰지 않기로 한 판단은 이 결정으로 대체된다.

## 상황
tailnet 의 다른 기기(핸드폰)에서도 Kubeflow 를 쓰고 싶다. 0009 에서 port-forward 와 NodePort 두 방식을 만들어 비교했는데, 그 구성은 Kubeflow 의 접속 안내를 읽기 **전에** 만든 것이었다. 안내를 읽고 시험해 보니 NodePort 에 근본적인 문제가 있었다.

## 결정
1. 게이트웨이 `istio-ingressgateway` Service 는 **공식 구성 그대로 ClusterIP** 로 둔다.
2. 이 PC: [07-1](../../scripts/07-1-port-forward.sh) 이 systemd 로 `kubectl port-forward` 를 `127.0.0.1:8080` 에 유지한다. 접속은 `http://localhost:8080` (Windows 브라우저도 mirrored 네트워킹으로 된다).
3. 다른 기기: [07-3](../../scripts/07-3-tailscale-serve.sh) 이 `tailscale serve --bg --https=443 http://127.0.0.1:8080` 으로 **HTTPS** 를 연다.
4. **NodePort([07-2](../../scripts/07-2-nodeport.sh))는 쓰지 않는다.** 시험과 기록을 위해 스크립트는 남기고 "사용하지 않음" 을 표시했다.

## NodePort 를 쓰지 않는 이유

| # | 이유 | 근거 | 확인 수준 |
|---|---|---|---|
| 1 | **공식이 권하지 않는다.** "보안상 서비스는 ClusterIP 만 쓰고 NodePort 나 그와 비슷하게 위험한 것은 쓰지 않는다" | [kubeflow/community-distribution](https://github.com/kubeflow/community-distribution) 의 NodePort / LoadBalancer / Ingress 절 | 공식 문서 인용 |
| 2 | **localhost 가 아닌 주소에 HTTP 로 접속하면 웹앱이 깨진다.** Jupyter, Tensorboard, Katib UI 가 Secure 쿠키를 쓰기 때문이다. NodePort 는 TLS 를 끝내 주는 곳이 없어서 HTTP 로만 열리고, 그래서 이 문제를 NodePort 만으로는 풀 수 없다 | 같은 공식 문서의 문장. 서버 실측(2026-10-26, curl): Jupyter 웹앱이 HTTP 응답으로 `Set-Cookie: XSRF-TOKEN=…; Secure; Path=/jupyter; SameSite=Strict` 를 내려준다. 반면 oauth2-proxy 세션 쿠키는 `Secure` 가 아니어서 로그인 화면까지는 된다 | 서버 쪽 `Secure` 속성은 실측. 브라우저가 저장을 거부해 Notebook 생성이 실패한다는 것은 공식 문서와 브라우저 표준 동작에서 **추정**, 브라우저로 시험하지 않았다 |
| 3 | **Kubeflow 의 기본 NetworkPolicy 를 열어야 동작한다.** `istio-system` 의 정책이 게이트웨이 8080 을 같은 네임스페이스와 `knative-serving` 에서만 허용해서 NodePort 로 들어온 노드 출발 트래픽이 막힌다. 모든 출발지에 8080 을 여는 정책을 더해서야 접속됐다 | 실측: 노드 안 `localhost:30080`, 파드 IP, ClusterIP 모두 타임아웃, 같은 노드에서만 302, 정책 없는 CoreDNS 로의 노드 간 통신은 정상 ([troubleshooting.md](../troubleshooting.md) 23번) | 실측. kindnet 이 정책을 집행한다는 것은 추정 |
| 4 | **노출 면이 넓다.** NodePort 는 모든 노드에서 같은 포트를 연다. 여기에 호스트 포트 매핑까지 더해진다 | Kubernetes Service 문서: "Each node proxies that port (the same port number on every Node) into your Service" | 공식 문서 인용 |
| 5 | **클러스터를 만들 때 묶인다.** 호스트 포트는 `kind-config.yaml` 의 `extraPortMappings` 로만 열 수 있어서, 포트나 바인딩 주소를 바꾸려면 클러스터를 지우고 다시 만들어야 한다 | kind 문서는 필드만 설명하고 "생성 후 변경 불가" 문장은 찾지 못했다. 구조(노드가 컨테이너)에서 나온 추론 | 추정 |
| 6 | **운영 부담이 늘고 공식 구성과 어긋난다.** `06` 을 다시 실행하면 Service 가 ClusterIP 로 돌아가 `07-2` 를 다시 해야 하고, 정책 하나와 Service 패치 하나를 따로 관리하며 검증 스크립트도 따로 둬야 한다 | 설계상 그렇다. Service 가 되돌아간다는 것은 시험하지 않았다 | 추정 |
| 7 | **이 PC 의 Windows 브라우저로는 쓸 수 없다.** 호스트 포트가 tailnet 주소에만 바인딩되는데 Tailscale 이 WSL 안에만 있어서 Windows 에 그 주소가 없다 | 실측: Windows 에서 `:30080` 타임아웃, `ipconfig` 에 주소 없음, `localhost:30080` 거부 | 실측 |
| 8 | **재부팅 후 동작을 시험하지 못했다.** port-forward 는 재부팅 시험을 통과했다 | [ADR 0010](0010-reboot-recovery.md) | 미시험 |

### NodePort 의 장점도 있었다
상시 도는 프로세스가 없고 파드가 바뀌어도 끊기지 않는다. 이 프로젝트는 사용자 한 명의 실습 환경이라 이 장점이 위 단점(특히 1~3)을 상쇄하지 못한다고 판단했다.

## 대안 비교

| 방식 | 공식 부합 | 접속 주소 | HTTPS | 이 PC | 다른 기기 | 상태 |
|---|---|---|---|---|---|---|
| port-forward `127.0.0.1` (07-1) | 공식 기본 방식 | `http://localhost:8080` | 필요 없음 (localhost 는 Secure 쿠키 예외) | 됨 | 안 됨 | 재부팅까지 시험함 |
| port-forward + `tailscale serve` (07-1 + 07-3) | ClusterIP 유지, TLS 는 앞단에서 종료 | `https://<기기>.<tailnet>.ts.net` | 됨 (Tailscale 이 인증서 발급) | 됨 (localhost) | 됨 | **미시험** |
| NodePort (07-2) | 비권장 | `http://<tailnet 주소>:30080` | 안 됨 | 안 됨 | HTTP 로만 | 접속은 확인, 웹앱은 깨질 것으로 추정 |

## 미검증과 위험 (HTTPS 경로)
- (확인됨, 2026-10-26) MagicDNS 와 HTTPS 인증서가 켜져 있어 `tailscale serve --bg --https=443` 이 성공했고 `tailscale serve status` 가 `https://<기기>.<tailnet>.ts.net (tailnet only)` 를 보여 준다.
- (확인됨, 서버 쪽) 로그인 리다이렉트가 `https://` 를 유지한다 ([verify/07-3](../../scripts/verify/07-3-tailscale-serve.sh) 통과). oauth2-proxy 의 `FORCE_HTTPS` 를 바꿀 필요가 없었다. 이후의 로그인 완료와 콜백은 브라우저로 확인해야 한다.
- HTTPS 로 접속한 뒤 **Notebook 생성이 실제로 되는지**. 이것이 이 결정의 핵심 시험이다.
- `APP_SECURE_COOKIES=false` 로 우회하는 방법은 쓰지 않는다 (공식: 보안 위험).
- `tailscale serve --bg` 가 재부팅 뒤 자동으로 다시 공유한다는 것은 Tailscale 문서의 설명이고, 이 PC 에서 시험하지 않았다.

## 접속할 때 헷갈리는 점 (2026-10-26 에 실제로 겪음)
- **`https://127.0.0.1:8080` / `https://localhost:8080` 은 `ERR_SSL_PROTOCOL_ERROR`.** 8080 은 TLS 가 없는 평문 포트다. 이 PC 는 `http://localhost:8080` 을 쓴다.
- **`https://<기기>.<tailnet>.ts.net` 이 이 PC 의 Windows 브라우저에서는 `DNS_PROBE_FINISHED_NXDOMAIN`.** `.ts.net` 이름은 Tailscale 이 설치되어 tailnet 에 연결된 기기에서만 해석된다. 이 PC 의 Windows 는 tailnet 노드가 아니다 (Tailscale 이 WSL 안에만 있다). 핸드폰처럼 tailnet 에 연결된 기기에서 연다.

## 시험 절차 (사용자 실행, WSL)
1. 수동으로 띄운 `kubectl port-forward`(pid 58715, 127.0.0.1:8080)를 종료한다: `kill 58715`
2. `bash scripts/07-1-port-forward.sh` -> `bash scripts/verify/07-1-port-forward.sh`, 이 PC 에서 `http://localhost:8080`
3. Tailscale 관리 콘솔 DNS 페이지에서 MagicDNS 와 HTTPS Certificates 를 켠다.
4. `bash scripts/07-3-tailscale-serve.sh` -> `bash scripts/verify/07-3-tailscale-serve.sh`
5. 핸드폰에서 출력된 `https://…ts.net` 주소로 접속, 로그인, **Notebook 생성**
6. 쓰지 않는 NodePort 설정 정리 (클러스터를 다시 만들면 저절로 사라진다): `kubectl --context kind-mlops -n istio-system delete networkpolicy allow-ingress-to-gateway-nodeport`. Service 를 ClusterIP 로 되돌리는 방법은 `06` 재실행이다 (되돌아가는지는 시험 전)
