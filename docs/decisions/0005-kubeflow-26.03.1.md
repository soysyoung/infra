# 0005. Kubeflow 26.03.1 (Pipelines, Notebooks, KServe)

- 상태: 설치 완료, 검증 통과 (2026-10-23)

## 결정
Kubeflow Community Distribution **26.03.1** (2026-06-15). 설치 구성요소는 **Pipelines, Notebooks(v1), KServe** 와 이들이 의존하는 공통요소다.

## 근거
- 26.03 이후 첫 패치 릴리스. CI 가 Kubernetes 1.36 에서 돈다.
- **26.10 은 아직 나오지 않았다** (GitHub 릴리스 최신이 26.03.1, 2026-10-23 확인). 설치 시점에도 같았다.
- 번들 구성요소: Istio 1.30.1, Knative 1.22.0, cert-manager 1.20.2, Pipelines 2.16.1, KServe 0.18.0. 따로 고르지 않는다.
- 권장 자원은 RAM 16GB 이상. 이 PC(WSL 24GB, 4노드 유휴 오버헤드 약 1.26GiB)로 가능하다.

## 구성 ([k8s/kubeflow/kustomization.yaml](../../k8s/kubeflow/kustomization.yaml))
공식 `example/kustomization.yaml` 에서 **선택하지 않은 줄만 주석 처리**한 것이다. 공식 example 과의 차이가 줄 단위로 보인다.

| 설치 | 이유 |
|---|---|
| Istio | 대시보드, Pipelines, Notebooks 대부분이 트래픽 보안, 인가, 라우팅에 쓴다. 인증(Dex, oauth2-proxy)도 Istio Ingress Gateway 위에서 동작한다. 필수. |
| Knative Serving | KServe 의 기본 배포 모드(`defaultDeploymentMode: "Serverless"`)가 Knative 를 쓴다. 기본값을 따른다. |
| cert-manager, Dex, oauth2-proxy | 인증서와 로그인. 필수. |
| Pipelines (SeaweedFS 스토리지), Central Dashboard, Notebooks v1, KServe + models web app, 사용자 네임스페이스 | 요청한 구성요소와 UI. |

**제외**: Katib, Trainer, Spark Operator, Hub(Model Registry, Model Catalog). 빌드 결과(596개 리소스)에 해당 워크로드가 없음을 확인했다. 공식 요청량 표 기준으로 Hub 만 빼도 메모리 약 2.1GiB, 디스크 20GB 를 아낀다.

## 도구와 테스트 조합
- kustomize **v5.8.1** (공식 테스트 스크립트의 버전. 앞서 후보로 적은 5.7.1 은 1.11 문서의 값이라 틀렸다).
- 공식 테스트 조합은 kind v0.32.0 + 노드 v1.36.1 이다. 우리는 kind v0.33.0 + 노드 v1.36.4(같은 1.36 마이너)라서, 설치 중 이상이 생기면 이 차이를 가장 먼저 의심한다.

## 주의
- 커뮤니티는 연 2회(26.03, 26.10) 릴리스하고 각 릴리스를 약 6개월 best-effort 로 지원한다. 26.03 은 2026-03-22 출시라 **지원 기간이 끝났을 수 있다.** 포트폴리오 시연용 단일 PC 에서는 26.03.1 을 고정해도 되지만 알고 쓴다.
- **기본 로그인(user@example.com / 12341234)은 공개된 값이다.** 클러스터 API 는 tailnet 에서만 열려 있고 접속은 `kubectl port-forward` 로 하지만, 비밀번호를 바꾸기 전에는 외부에 노출하지 않는다.
- Katib/Notebooks 의 개별 버전은 확인하지 못했다 (Katib 은 제외, Notebooks 는 v1).
- 설치 결과 (2026-10-23): 파드 64개가 모두 Running/Completed, Deployment 전부 Available, 로그인 흐름(oauth2-proxy -> Dex) 동작. 설치 중 겪은 문제는 [troubleshooting.md](../troubleshooting.md) 9~12번, 15번.
- 부하 (설치 후 유휴): WSL 사용 7.0Gi (가용 16Gi), 노드 컨테이너 합계 약 7.8GiB (control-plane 1.7, CPU 워커 각 2.8~3.0, GPU 워커 0.27). 24GB 할당으로 충분하다.
- **로그인 후 기능(Pipelines 실행, Notebook 생성, GPU Notebook)은 아직 시험하지 않았다.**

## 재검토 시점
26.10 이 나오면(설치 전이면 그 버전으로), 설치 후에는 지원 종료 시점. Katib/Trainer 가 필요해지면 주석을 푼다.

## 출처 (확인 2026-10-23)
- https://github.com/kubeflow/community-distribution/releases
- https://github.com/kubeflow/community-distribution (README: 설치, 요청량 표, 사전 요구)
- 26.03.1 태그의 `example/kustomization.yaml`, `tests/install_KinD_create_KinD_cluster_install_kustomize.sh`
