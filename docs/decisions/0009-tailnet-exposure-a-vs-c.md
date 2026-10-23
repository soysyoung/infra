# 0009. Kubeflow 를 tailnet 에 여는 방식: A (port-forward 서비스) 와 C (NodePort 직결)

- 상태: 두 방식 모두 구성함, **둘 다 이 PC 에서 아직 시험하지 못했다** (2026-10-23)

## 상황
`kubectl port-forward` 는 `127.0.0.1` 에만 열리고 터미널을 닫으면 끊긴다. 다른 기기에서 tailnet 주소로 Kubeflow 를 상시 쓰려면 tailnet 주소에서 받아 주는 경로가 필요하다. 접속은 Tailscale 하나로 일원화하고 공유기 포트포워딩은 쓰지 않는다 ([architecture.md](../architecture.md)).

## 결정
두 방식을 모두 만들고, 포트가 달라서 한 클러스터에서 공존한다. 상시 사용은 시험한 뒤에 정한다. 선호는 C 이고 A 를 먼저 만든 이유는 기존 클러스터에 바로 적용되기 때문이다.

| | A. systemd 로 감싼 port-forward | C. NodePort 직결 |
|---|---|---|
| 접속 주소 | `http://<tailnet 주소>:8080` | `http://<tailnet 주소>:30080` |
| 구성 위치 | `scripts/07-expose.sh` 가 `/etc/systemd/system/kubeflow-port-forward.service` 를 만든다 | `k8s/kind-config.yaml` 의 `extraPortMappings` (호스트 `<tailnet 주소>:30080` -> 노드 30080) + `k8s/kubeflow/kustomization.yaml` 의 patch (게이트웨이 Service 를 NodePort 30080 으로) |
| 동작 | `kubectl port-forward` 프로세스 하나가 파드 하나로 터널을 연다 (API 서버를 거친다) | Docker 가 포트를 노드 컨테이너로 넘기고 kube-proxy 가 서비스로 분배한다. 상시 도는 별도 프로세스가 없다 |
| 파드가 바뀌면 | 터널이 끊긴다. systemd 가 5초 뒤 다시 붙인다 | 서비스 라우팅이라 영향이 없다 |
| 언제 적용되나 | 아무 때나, 기존 클러스터에도 | 매핑은 **클러스터를 만들 때만** 정해진다. 이미 만든 클러스터는 지우고 `05-1` 부터 다시 해야 한다 (Service patch 만은 `06` 재실행으로 들어간다) |
| 재부팅 후 | Docker, tailscaled, 클러스터가 늦으면 서비스가 재시도한다 | tailscaled 가 Docker 보다 늦으면 노드 컨테이너 자체가 시작에 실패할 수 있다 (API 서버 6443 의 기존 열린 항목과 같은 위험) |
| 공식 구성과의 차이 | 없음 | 게이트웨이 Service 의 type 과 nodePort 를 바꾼다 (patch 한 곳) |
| 삭제 | `teardown/07-expose.sh` 가 서비스를 지운다 | 클러스터와 함께 사라진다 |

공통: 둘 다 tailnet 주소에만 바인딩한다 (`0.0.0.0` 이 아니므로 LAN 에 열리지 않는다). 로그인 쿠키는 `FORCE_HTTPS=false` 라서 `Secure` 속성이 없고 http 로 로그인할 수 있다 (oauth2-proxy 매니페스트에서 확인). 콜백 주소(`/oauth2/callback`)는 상대 경로다. 다만 localhost 가 아닌 tailnet 주소로 실제 로그인이 되는지는 시험하지 못했다.

## 검토했으나 쓰지 않은 것
`tailscale serve` 로 로컬 8080 을 노출하는 방법. 명령 하나로 되지만 결국 port-forward 가 떠 있어야 해서 A 의 문제가 그대로 남고, 동작과 재부팅 후 유지 여부를 확인하지 못했다.

## 미검증
- `scripts/verify/07-expose.sh` 를 아직 실행하지 않았다 (A 와 C 를 각각 확인하고 하나라도 되면 통과한다).
- 위 표의 "파드가 바뀌면", "재부팅 후" 행은 구조에서 나온 추론이다.
- kustomize 빌드에서 `nodePort: 30080` 이 들어가는 것만 확인했다. 클러스터에 적용해 보지 않았다 (병합 키에 `protocol: TCP` 가 없으면 nodePort 가 사라지는 것을 빌드에서 확인하고 고쳤다).
