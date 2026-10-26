# infra

노트북(Windows 11 + WSL2 + RTX 5080)을 원격 MLOps 서버로 만드는 프로젝트. Tailscale, Docker, kind, Kubeflow 를 셸 스크립트로 설치하고, 이후 Terraform 으로 코드화한다. 모든 버전은 최신이 아니라 안정성 기준으로 골랐고, 근거는 문서에 남긴다.

## 시작

- 설치: [scripts/README.md](scripts/README.md) (사전 요구, 실행 순서, Kubeflow 접속)
- 검증: [scripts/verify/README.md](scripts/verify/README.md)
- 삭제: [scripts/teardown/README.md](scripts/teardown/README.md)

## 상태

- 2026-10-23 (1차 설치): `00` ~ `06` 전체 설치와 검증 통과 (kind 4노드, GPU 노드의 파드에서 RTX 5080 확인, Kubeflow 26.03.1 로그인 흐름). 이어서 삭제 스크립트로 WSL 까지 지웠다.
- 2026-10-23 (재설치, **진행 중**): 처음부터 다시 설치해 `06` 까지 실행했다. 각 단계의 검증 결과는 아직 기록하지 않았다 (`scripts/verify/README.md` 에 실행 후 반영). 로그인 비밀번호는 `.env` 로 정한다.
- 2026-10-23: `.env` 비밀번호 반영(`06`)과 tailnet 상시 접속 port-forward 방식(`07-1-port-forward.sh`)을 실행했고, 핸드폰에서 `http://<tailnet 주소>:8080` 접속과 새 비밀번호 로그인을 확인했다 ([ADR 0009](docs/decisions/0009-tailnet-exposure-port-forward-vs-nodeport.md)).
- 2026-10-26: Kubeflow 공식 접속 안내를 읽고 접속 구성을 바꿨다 ([ADR 0011](docs/decisions/0011-no-nodeport-https-via-tailscale-serve.md)). NodePort 는 쓰지 않고(공식 비권장, HTTP 로는 웹앱이 깨짐), 게이트웨이는 ClusterIP, 이 PC 는 `http://localhost:8080`, 다른 기기는 `tailscale serve` HTTPS.
- 2026-10-26: `07-1`(port-forward `127.0.0.1`)과 `07-3`(tailscale serve HTTPS)의 서버 쪽 검증이 통과했고 로그인 리다이렉트가 `https://` 를 유지한다.
- **아직 시험하지 못한 것**: 핸드폰 브라우저에서 HTTPS 로그인과 Notebook 생성, 재부팅 후 `tailscale serve` 자동 재개, `03` 의 `docker.sources` 등록, 삭제의 수정 경로.
- 2026-10-23: 재부팅 후 자동 복구를 구성했다: `windows/autostart.ps1`(부팅 때 WSL 유지), `windows/power-settings.ps1`, kind 노드 재시작 정책(`05-1`), `scripts/verify/08-reboot.sh` ([ADR 0010](docs/decisions/0010-reboot-recovery.md)). 2026-10-26 '다시 시작' 재부팅 시험 1회 통과 (WSL, 서비스, 노드, Kubeflow 접속이 사람의 조작 없이 돌아옴).
- 다음 할 일과 시험 목록은 [docs/todo.md](docs/todo.md).

## 문서

| 문서 | 내용 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | 구성도와 설계 원칙 |
| [docs/versions.md](docs/versions.md) | 버전 표와 선택 근거, 미검증 항목 |
| [docs/decisions/](docs/decisions/) | 결정 기록 (ADR 0001 ~ 0011) |
| [docs/todo.md](docs/todo.md) | 앞으로 할 일과 시험 순서 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 막힌 곳과 해결 (표). 상세 기록은 [docs/archive/](docs/archive/) |
| [docs/ai-usage.md](docs/ai-usage.md) | 생성형 AI 사용 기록, AI 의 판단을 바로잡은 사례 |
| [docs/commit-convention.md](docs/commit-convention.md) | 커밋 규칙 |

## 브랜치

작업은 `dev` 에서 하고, `main` 은 검증을 마친 뒤 합친다.
