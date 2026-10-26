# 0009. Kubeflow 를 tailnet 에 여는 방식: port-forward (systemd 서비스) 와 NodePort (직결)

- 상태: 두 방식 모두 구성함. **port-forward 방식은 시험함** (2026-10-23: `06` 재실행 -> `07-expose.sh`(지금의 `07-1-port-forward.sh`) -> `verify/07-expose.sh`(지금의 `verify/07-1-port-forward.sh` 와 `07-2-nodeport.sh` 로 나뉨) 를 실행했고 핸드폰에서 `http://<tailnet 주소>:8080` 접속과 `.env` 의 새 비밀번호로 로그인을 확인했다). **NodePort 방식은 아직 시험하지 못했다** (클러스터를 다시 만들어야 한다)

## 상황
`kubectl port-forward` 는 `127.0.0.1` 에만 열리고 터미널을 닫으면 끊긴다. 다른 기기에서 tailnet 주소로 Kubeflow 를 상시 쓰려면 tailnet 주소에서 받아 주는 경로가 필요하다. 접속은 Tailscale 하나로 일원화하고 공유기 포트포워딩은 쓰지 않는다 ([architecture.md](../architecture.md)).

## 결정
두 방식을 모두 만들고, 포트가 달라서 한 클러스터에서 공존한다. 상시 사용은 시험한 뒤에 정한다. 선호는 NodePort 방식이고 port-forward 방식을 먼저 만든 이유는 기존 클러스터에 바로 적용되기 때문이다.

| | port-forward (systemd 로 감쌈) | NodePort (직결) |
|---|---|---|
| 접속 주소 | `http://<tailnet 주소>:8080` | `http://<tailnet 주소>:30080` |
| 구성 위치 | `scripts/07-1-port-forward.sh` 가 `/etc/systemd/system/kubeflow-port-forward.service` 를 만든다 | 호스트 포트는 `k8s/kind-config.yaml` 의 `extraPortMappings` (호스트 `<tailnet 주소>:30080` -> 노드 30080, `05-1` 이 클러스터를 만들 때), Service 변경은 `scripts/07-2-nodeport.sh` 가 한다 |
| 동작 | `kubectl port-forward` 프로세스 하나가 파드 하나로 터널을 연다 (API 서버를 거친다) | Docker 가 포트를 노드 컨테이너로 넘기고 kube-proxy 가 서비스로 분배한다. 상시 도는 별도 프로세스가 없다 |
| 파드가 바뀌면 | 터널이 끊긴다. systemd 가 5초 뒤 다시 붙인다 | 서비스 라우팅이라 영향이 없다 |
| 언제 적용되나 | 아무 때나, 기존 클러스터에도 | 매핑은 **클러스터를 만들 때만** 정해진다. 매핑이 없는 클러스터면 `07-2` 가 알려 주고 멈춘다. 지우고 `05-1` 부터 다시 해야 한다. `06` 을 다시 실행하면 Service 가 되돌아가서 `07-2` 도 다시 실행한다 |
| 재부팅 후 | Docker, tailscaled, 클러스터가 늦으면 서비스가 재시도한다 | tailscaled 가 Docker 보다 늦으면 노드 컨테이너 자체가 시작에 실패할 수 있다 (API 서버 6443 의 기존 열린 항목과 같은 위험) |
| 공식 구성과의 차이 | 없음 | 없음. Kubeflow 매니페스트(`k8s/kubeflow/kustomization.yaml`)는 건드리지 않고, 설치 뒤 `07-2` 가 Service 하나를 패치하고 NetworkPolicy 하나를 더한다 |
| 삭제 | `teardown/07-1-port-forward.sh` 가 서비스를 지운다 | 클러스터와 함께 사라진다 (삭제 스크립트 없음) |

공통: 둘 다 tailnet 주소에만 바인딩한다 (`0.0.0.0` 이 아니므로 LAN 에 열리지 않는다). 로그인 쿠키는 `FORCE_HTTPS=false` 라서 `Secure` 속성이 없고 http 로 로그인할 수 있다 (oauth2-proxy 매니페스트에서 확인). 콜백 주소(`/oauth2/callback`)는 상대 경로다. tailnet 주소(http)로 실제 로그인이 되는 것은 port-forward 방식으로 확인했다 (핸드폰, 2026-10-23).

## 시험에서 드러난 것: NodePort 는 NetworkPolicy 를 보완해야 한다 (2026-10-26)
NodePort 방식은 Service 만 바꿔서는 접속되지 않았다. `istio-system` 의 Kubeflow NetworkPolicy 가 게이트웨이 8080 을 같은 네임스페이스와 `knative-serving` 에서만 허용해서, NodePort 로 들어온 노드 출발 트래픽이 다른 노드의 게이트웨이 파드에서 막혔다. port-forward 는 kubelet 이 파드에 직접 연결하므로 이 정책을 거치지 않는다. 진단 과정과 실측값은 [troubleshooting.md](../troubleshooting.md) 23번.

- 대응: `07-2` 가 8080 을 모든 출발지에 여는 NetworkPolicy 하나를 더한다. 정책은 합집합으로 적용되어 기존 허용은 그대로다.
- 대가: 게이트웨이 8080 을 클러스터 안 모든 파드가 직접 부를 수 있게 된다 (이전에는 같은 네임스페이스와 knative 만). 인증은 앞단 oauth2-proxy 가 하고 이 클러스터는 사용자 한 명의 실습 환경이라 허용했다. 좁히려면 `from.ipBlock` 에 kind 도커 네트워크 대역을 쓴다 (미시험).
- 즉 NodePort 방식은 port-forward 보다 손이 더 간다. 비교표의 "상시 도는 프로세스가 없다" 는 장점은 그대로지만 설치가 간단하다는 인상은 틀렸다.

## 검토했으나 쓰지 않은 것
`tailscale serve` 로 로컬 8080 을 노출하는 방법. 명령 하나로 되지만 결국 port-forward 가 떠 있어야 해서 port-forward 방식의 문제가 그대로 남고, 동작과 재부팅 후 유지 여부를 확인하지 못했다.

## 공식 문서 대조 (2026-10-23)

이 ADR 의 구성은 처음에 클론한 Kubeflow 매니페스트와 제 기억으로 썼고, 쓴 **뒤에** 공식 문서와 대조했다.

| 대상 | 공식 문서가 말하는 것 | 이 구성 | 판정 |
|---|---|---|---|
| kind `extraPortMappings` | `containerPort`, `hostPort`, `listenAddress`(호스트 바인드 주소, 기본 0.0.0.0), `protocol` ([kind 설정](https://kind.sigs.k8s.io/docs/user/configuration/#extra-port-mappings)) | `containerPort`/`hostPort` 30080, `listenAddress` 를 tailnet 주소로 | 일치 |
| NodePort | 기본 범위 30000-32767, `nodePort` 로 직접 지정하면 할당되거나 실패, 충돌은 직접 관리 ([Service](https://kubernetes.io/docs/concepts/services-networking/service/)) | 30080 지정 | 일치 |
| `kubectl port-forward --address` | 쉼표로 여러 주소, IP 또는 localhost 만 허용, 기본 `localhost`(127.0.0.1 과 ::1) ([문서](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/)) | tailnet IP 하나 | 일치 |
| systemd `Restart=always` | 정상/비정상 종료, 시그널, 타임아웃 모두 재시작. systemd 가 직접 멈춘 경우는 제외 ([systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)) | `Restart=always`, `RestartSec=5` | 일치 |
| dex 정적 비밀번호 | `hash` 는 bcrypt 해시, 예시는 `htpasswd -BinC 10` ([dex 문서](https://dexidp.io/docs/connectors/local/)) | `06` 이 파이썬 bcrypt 로 만들고 접두사를 `$2y$` 로 맞춤 | 형식은 일치. 같은 문서에 `$2b$` 허용 여부는 없어서 접두사를 맞췄다 |
| `hashFromEnv`, `dex-passwords` 시크릿 | 이 문서 확인 못 함. 클론한 Kubeflow 매니페스트의 `config-map.yaml`, `dex-passwords.yaml` 에서 읽음 | 그 시크릿을 patch | 매니페스트 기준 (공식 문서 아님) |
| `FORCE_HTTPS=false`, 쿠키 `Secure` 없음 | 클론한 oauth2-proxy 매니페스트에서 읽음 | http 로그인 가능 | 매니페스트 기준 |

문서에서 확인하지 못한 것: kind 의 `extraPortMappings` 를 생성 후 바꿀 수 없다는 점(위 표의 kind 문서에 그런 문장이 없다. 노드가 컨테이너이고 포트 퍼블리시가 컨테이너 생성 시점에 정해지는 구조에서 나온 추론), `tailscale serve` 의 동작.

## 미검증
- `scripts/verify/07-1-port-forward.sh`, `07-2-nodeport.sh`: 나누기 전의 `07-expose.sh` 로 port-forward 방식만 실행했다 (사용자 보고, 출력은 첨부받지 못했다). NodePort 방식은 현재 클러스터에 포트 매핑이 없어 확인할 수 없다.
- port-forward 방식의 재부팅 후 동작은 2026-10-26 '다시 시작' 1회로 확인했다 ([ADR 0010](0010-reboot-recovery.md)).
- 위 표의 "파드가 바뀌면", "재부팅 후" 행은 구조에서 나온 추론이다.
- kustomize 빌드에서 `nodePort: 30080` 이 들어가는 것만 확인했다. 클러스터에 적용해 보지 않았다 (병합 키에 `protocol: TCP` 가 없으면 nodePort 가 사라지는 것을 빌드에서 확인하고 고쳤다).
