# infra

노트북(Windows 11 + WSL2 + RTX 5080)을 원격 MLOps 서버로 만드는 프로젝트. Tailscale, Docker, kind, Kubeflow 를 셸 스크립트로 설치하고, 이후 Terraform 으로 코드화한다. 모든 버전은 최신이 아니라 안정성 기준으로 골랐고, 근거는 문서에 남긴다.

## 시작

- 설치: [scripts/README.md](scripts/README.md) (사전 요구, 실행 순서, Kubeflow 접속)
- 검증: [scripts/verify/README.md](scripts/verify/README.md)
- 삭제: [scripts/teardown/README.md](scripts/teardown/README.md)

## 상태

- 2026-10-23 (1차 설치): `00` ~ `06` 전체 설치와 검증 통과 (kind 4노드, GPU 노드의 파드에서 RTX 5080 확인, Kubeflow 26.03.1 로그인 흐름). 이어서 삭제 스크립트로 WSL 까지 지웠다.
- 2026-10-23 (재설치, **진행 중**): 처음부터 다시 설치해 `06` 까지 실행했다. 각 단계의 검증 결과는 아직 기록하지 않았다 (`scripts/verify/README.md` 에 실행 후 반영). 로그인 비밀번호는 `.env` 로 정한다.
- 이번에 추가하고 **아직 시험하지 못한 것**: 비밀번호 반영(`06`), tailnet 상시 접속 방식 A (`07-expose.sh`) 와 C (kind `extraPortMappings` + NodePort), [ADR 0009](docs/decisions/0009-tailnet-exposure-a-vs-c.md). `03` 의 `docker.sources` 등록과 삭제의 수정 경로도 아직 실행해 보지 못했다.
- 다음: 재설치 검증 마무리, 로그인 후 기능 시험, autostart 와 재부팅 시험, IaC (Terraform).

## 문서

| 문서 | 내용 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | 구성도와 설계 원칙 |
| [docs/versions.md](docs/versions.md) | 버전 표와 선택 근거, 미검증 항목 |
| [docs/decisions/](docs/decisions/) | 결정 기록 (ADR 0001 ~ 0009) |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 막힌 곳과 해결 (표). 상세 기록은 [docs/archive/](docs/archive/) |
| [docs/ai-usage.md](docs/ai-usage.md) | 생성형 AI 사용 기록, AI 의 판단을 바로잡은 사례 |
| [docs/commit-convention.md](docs/commit-convention.md) | 커밋 규칙 |

## 브랜치

작업은 `dev` 에서 하고, `main` 은 검증을 마친 뒤 합친다.
