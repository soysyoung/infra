# infra

노트북(Windows 11 + WSL2 + RTX 5080)을 원격 MLOps 서버로 만드는 프로젝트. Tailscale, Docker, kind, Kubeflow 를 셸 스크립트로 설치하고, 이후 Terraform 으로 코드화한다. 모든 버전은 최신이 아니라 안정성 기준으로 골랐고, 근거는 문서에 남긴다.

## 범위

이 저장소는 **플랫폼(서버를 만드는 일)만** 다룬다. 그 위에서 도는 워크로드(파이프라인, 학습·추론 코드, 노트북 예제, 실험 기록)는 프로젝트마다 단독 저장소에 둔다. 첫 프로젝트는 [fashion-recsys-mlops](https://github.com/soysyoung/fashion-recsys-mlops) 다. 이 저장소가 제공하는 것(접속 주소, GPU PodDefault, GPU time-slicing, OpenSearch, PostgreSQL)은 문서로만 참조한다.

## 시작

- 설치: [scripts/README.md](scripts/README.md) (사전 요구, 실행 순서, Kubeflow 접속)
- 검증: [scripts/verify/README.md](scripts/verify/README.md)
- 삭제: [scripts/teardown/README.md](scripts/teardown/README.md)

## 상태

2026-10-26 기준 (플랫폼 서비스 줄은 2026-10-28). 새 세션에서 이어 하려면 [docs/todo.md](docs/todo.md) 를 먼저 읽는다.

- **동작 중**: kind 4노드(GPU 워커 포함) + Kubeflow 26.03.1. GPU 노드의 파드에서 RTX 5080 확인. 로그인 비밀번호는 `.env`.
- **플랫폼 서비스** (2026-10-28): GPU 1장을 time-slicing 으로 4개 광고(VRAM 은 나뉘지 않는다, [ADR 0013](docs/decisions/0013-gpu-time-slicing.md)). OpenSearch 3.8.0 단일 노드 + k-NN ([ADR 0014](docs/decisions/0014-opensearch-single-node.md)). 프로필 네임스페이스별 ResourceQuota 는 `06-4` 가 `quotas.env` 로 건다: 기본 사용자 GPU 3, 두 번째 사용자 GPU 0 ([ADR 0015](docs/decisions/0015-profile-resource-quota.md)). GPU 쿼터는 개수 배분일 뿐 메모리 보호가 아니다.
- **PostgreSQL** (2026-10-30): CloudNativePG 연산자(Helm) + 단일 인스턴스 PostgreSQL 18.6, 클러스터 안에서만 접근 ([ADR 0021](docs/decisions/0021-postgres-cloudnativepg.md)). 앱 계정 비밀번호는 공식 기본값과 달리 `.env` 에 둔다 (이유는 [scripts/README.md](scripts/README.md)). Notebook 에서는 기본 사용자 네임스페이스가 소유자 `app`, 공유용 네임스페이스가 읽기/쓰기 전용 `notebook_rw` 로 접속하고 비밀번호는 PostgreSQL 공식 권고인 password file 로 넣는다 ([ADR 0022](docs/decisions/0022-notebook-postgres-access.md)). 설치는 검증을 통과했고 guest Notebook 에서 password file 로그인까지 확인했다. user Notebook 의 password file 로그인, 백업, 재시작 뒤 데이터 보존, 메모리 측정, `teardown/10-2` 는 아직 하지 않았다 ([docs/todo.md](docs/todo.md) 31~36번).
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
| [docs/decisions/](docs/decisions/) | 결정 기록 (ADR 0001 ~ 0022) |
| [docs/todo.md](docs/todo.md) | 앞으로 할 일과 시험 순서 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 막힌 곳과 해결 (표). 상세 기록은 [docs/archive/](docs/archive/) |
| [docs/ai-usage.md](docs/ai-usage.md) | 생성형 AI 사용 기록, AI 의 판단을 바로잡은 사례 |
| [docs/commit-convention.md](docs/commit-convention.md) | 커밋 규칙 |

## 브랜치

작업은 `dev` 에서 하고, `main` 은 검증을 마친 뒤 합친다.
