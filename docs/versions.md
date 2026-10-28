# 버전 표

버전의 단일 출처는 [`versions.env`](../versions.env)다. 이 문서는 선택 근거와 확인일을 기록한다.
선택 기준은 **최신이 아니라 안정성**이다. 자세한 비교와 대안은 [`decisions/`](decisions/) 의 ADR 참고.

확인일: 2026-10-23

| 항목 | 선택 | 근거 | ADR |
|---|---|---|---|
| WSL 배포판 | Ubuntu 24.04 LTS | 지원이 2029년 4월까지. 26.04 는 출시 6개월차라 서드파티(NVIDIA, Docker) 검증이 얕다. | [0001](decisions/0001-ubuntu-2404.md) |
| Kubernetes 배포판 | kind v0.33.0 (2026-08-26) | 런타임이 Docker 하나, Kubeflow 공식 테스트 환경, 클러스터 재생성이 쉬워 IaC 에 유리. GPU 검증 완료 ([0006](decisions/0006-nvidia-wsl2-blackwell.md)). | [0002](decisions/0002-kind-over-k3s.md) |
| 노드 이미지 | kindest/node v1.36.4 (digest 고정) | kind v0.33.0 이 제공하는 1.36 이미지. Kubeflow 26.03.1 의 CI 버전(1.36)과 같은 마이너. 1.37 은 Kubeflow 가 검증하지 않아 제외. | [0003](decisions/0003-kubernetes-1.36-pinned-to-kubeflow.md) |
| Docker Engine | 29.8.2 (2026-09-30), apt hold | 직전 마이너의 마지막 패치. 다음 마이너(29.9.0) 후 2주 이상 경과. | [0004](decisions/0004-docker-single-runtime.md) |
| Kubeflow | 26.03.1 (2026-06-15) | 26.03 의 첫 패치. CI 가 Kubernetes 1.36. 26.10 은 아직 없음(2026-10-23 확인). 지원 기간 주의(ADR 참고). 구성요소: Pipelines, Notebooks, KServe. | [0005](decisions/0005-kubeflow-26.03.1.md) |
| NVIDIA Container Toolkit | 1.20.1 | WSL2 CDI 수정 포함. Windows 드라이버만 사용(현재 592.27). | [0006](decisions/0006-nvidia-wsl2-blackwell.md) |
| kubectl | v1.36.4 | 노드 이미지와 같은 버전. 체크섬 검증 후 설치. | [0003](decisions/0003-kubernetes-1.36-pinned-to-kubeflow.md) |
| NVIDIA device plugin | v0.20.1 (2026-09-22) | Codex 조사 + 릴리스 목록으로 확인. GPU Operator 는 쓰지 않음. | [0006](decisions/0006-nvidia-wsl2-blackwell.md) |
| Terraform | 후보 1.17.0 | IaC 단계에서 확정. | - |
| kustomize | v5.8.1 | Kubeflow 26.03.1 공식 테스트 스크립트의 버전. 체크섬 검증 후 설치. | [0005](decisions/0005-kubeflow-26.03.1.md) |
| OpenSearch (Helm 차트) | 3.8.0 (2026-08-05) | 직전 마이너 기준. 3.9.0(2026-09-29)은 한 달밖에 안 됐고 3.8 에는 패치 릴리스가 없다. 차트와 앱 버전이 같다. 보안 플러그인의 초기 관리자 비밀번호가 필수다. | [0014](decisions/0014-opensearch-single-node.md) |
| Helm | v4.2.4 (2026-08-13) | 4.3.0(2026-09-09)이 2주 넘게 지나서 직전 마이너 4.2 의 마지막 패치. 체크섬 검증 후 설치. | [0014](decisions/0014-opensearch-single-node.md) |

## 미검증 항목

- kind 안의 파드의 실제 CUDA 연산 (`nvidia-smi -L` 까지만 확인했다. kind 안의 GPU 인식은 2026-10-23 에 검증 완료)
- Kubeflow 로그인 후 기능 (Pipelines 실행, Notebook 생성, GPU Notebook). 설치와 로그인 흐름까지만 검증했다
- Docker 29 최소 API(1.44) 와 kind v0.33.0 의 호환 (문제 보고는 못 찾음)
- Codex 교차 리뷰는 완료했으나 Codex 도 이 PC 의 실제 환경은 검증하지 못했다 ([ai-usage.md](ai-usage.md))
