# infra

노트북(Windows 11 + WSL2 + RTX 5080)을 원격 MLOps 서버로 만드는 프로젝트. Tailscale, Docker, kind, Kubeflow 를 셸 스크립트로 설치하고, 이후 Terraform 으로 코드화한다. 모든 버전은 최신이 아니라 안정성 기준으로 골랐고, 근거는 문서에 남긴다.

## 범위

이 저장소는 **플랫폼(서버를 만드는 일)만** 다룬다. 그 위에서 도는 워크로드(파이프라인, 학습·추론 코드, 노트북 예제, 실험 기록)는 별도 저장소에 둘 예정이다 (아직 만들지 않았다).

## 시작

- 설치: [scripts/README.md](scripts/README.md) (사전 요구, 실행 순서, Kubeflow 접속)
- 검증: [scripts/verify/README.md](scripts/verify/README.md)
- 삭제: [scripts/teardown/README.md](scripts/teardown/README.md)

## 상태

2026-10-26 기준. 새 세션에서 이어 하려면 [docs/todo.md](docs/todo.md) 를 먼저 읽는다.

- **동작 중**: kind 4노드(GPU 워커 포함) + Kubeflow 26.03.1. GPU 노드의 파드에서 RTX 5080 확인. 로그인 비밀번호는 `.env`.
- **접속**: 이 PC 는 `http://localhost:8080`, 핸드폰 등 tailnet 기기는 `tailscale serve` 의 HTTPS 주소. NodePort 는 쓰지 않는다 ([ADR 0011](docs/decisions/0011-no-nodeport-https-via-tailscale-serve.md)). 핸드폰에서 로그인하고 Notebook 을 만들었다 (파드 2/2 Running, 91초). 만든 Notebook 을 JupyterLab 으로 열어 코드를 실행했다 (웹소켓 통과).
- **재부팅**: 예약 작업이 로그온 없이 WSL 을 띄우고 노드가 저절로 올라온다. '다시 시작' 2회 통과, 두 번째에는 `tailscale serve` 의 HTTPS 주소와 GPU 광고도 유지됐다 ([ADR 0010](docs/decisions/0010-reboot-recovery.md)).
- **기능 시험 통과**: GPU Notebook (GPU 워커의 taint 용 PodDefault [k8s/gpu-poddefault.yaml](k8s/gpu-poddefault.yaml) 필요), Pipelines (다중 사용자 모드라 Experiment 를 먼저 만든다).
- **아직 시험하지 못한 것**: 삭제 중 `docker0` 인터페이스 제거의 확인 (패키지 purge 는 2026-10-27 실제 삭제에서 확인).
- **남겨 둔 것**: `07-2` 스크립트 (시험 기록, 30080 매핑은 2026-10-27 에 `kind-config.yaml` 에서 제거). kind API 서버는 `127.0.0.1` 에만 연다 ([ADR 0010](docs/decisions/0010-reboot-recovery.md)). 공식 문서 재대조 결과와 열린 항목은 [ADR 0012](docs/decisions/0012-official-doc-recheck.md).
- 이력: 2026-10-23 처음부터 재설치와 검증, 2026-10-26 재부팅 복구, 접속 방식 결정, 쿠키 문제 해결, 기능 시험, 공식 문서 재대조.

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
