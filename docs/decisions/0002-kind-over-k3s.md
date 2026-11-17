# 0002. Kubernetes 는 k3s 가 아니라 kind

- 상태: **확정** (2026-10-23, GPU 2차 관문 통과)

## 상황
단일 노드 노트북에서 Kubeflow 를 돌릴 Kubernetes 배포판을 정한다. 처음에는 k3s 를 제안했으나, 다음 사실 때문에 kind 로 바꿨다.
- k3s 는 자체 containerd 를 쓰므로 Docker 와 런타임이 둘이 된다. Docker 로 빌드한 이미지가 k3s 에서 보이지 않아 레지스트리가 필수가 된다.
- Kubeflow 문서는 kind 를 기본 테스트 환경으로 쓴다 ("We use Kind as default").

## 결정
**kind v0.33.0** + Docker Engine. 런타임은 Docker 하나다. 이미지는 `kind load docker-image` 로 넣는다.

## 비교
| | kind | k3s |
|---|---|---|
| 런타임 | Docker 하나 | containerd + Docker, 사이에 레지스트리 |
| Kubeflow | 공식 테스트 경로 | 동작은 하나 비공식 |
| IaC | 클러스터 삭제/재생성이 쉽다 | 호스트 서비스라 Terraform 에 어색 |
| 데이터 | 클러스터 삭제 시 PV 소실 -> extraMounts 로 호스트에 보존 | 호스트에 남는다 |
| GPU | 까다롭다 (WSL2 에서 더) | 호스트 containerd 에 nvidia 런타임만 설정 |

## 결과
- 03 docker -> 04 nvidia-toolkit -> 05 kind(05-1 ~ 05-3) 순서. 노드 구성은 [0007](0007-multi-node-kind.md). `03-k3s.sh` 는 삭제했다.
- `k8s/kind-config.yaml` 이 필요하다: 노드 이미지 digest, 원격 접속용 `certSANs`(tailnet 주소), `extraMounts`, 포트 매핑.
- Tailscale(02)이 kind(05)보다 먼저여야 한다 (인증서 SAN).
- 레지스트리는 필수가 아니다. 필요해지면 kind 공식 로컬 레지스트리 패턴으로 추가한다.
- `01-wsl-systemd.sh` 는 tailscaled 와 Docker 가 systemd 를 쓰므로 계속 필요하다.

## 확정 조건과 대안
**GPU 관문**: 1차(Docker 컨테이너의 `nvidia-smi`, `verify/04-gpu.sh`)와 2차(GPU 노드의 파드가 GPU 를 잡음, `verify/05-3-device-plugin.sh`)를 모두 통과해서 kind 로 확정했다. 2차에서는 Codex 레시피에 없던 노드 후처리가 필요했다. 레시피와 한계는 [0006](0006-nvidia-wsl2-blackwell.md) 참고.
실패하면 k3s 로 돌아간다: 런타임 둘 + 레지스트리 구성, k3s `v1.36.5+k3s1`(stable 채널), 설치 시 `--disable traefik`(Kubeflow 의 Istio 와 충돌).

## 재검토 시점
GPU 관문 결과가 나왔을 때. 이후에는 kind 에서 PV 보존 문제가 커질 때.

## 출처 (확인 2026-10-23)
- https://github.com/kubeflow/community-distribution (Prerequisites: kind, podman 또는 docker)
- https://kind.sigs.k8s.io/
- https://docs.k3s.io/upgrades/manual (릴리스 채널), https://update.k3s.io/v1-release/channels
