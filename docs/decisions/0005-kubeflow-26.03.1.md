# 0005. Kubeflow 26.03.1

- 상태: 채택, 지원 기간 주의 (2026-10-23)

## 결정
Kubeflow Community Distribution **26.03.1** (2026-06-15).

## 근거
- 26.03 이후 첫 패치 릴리스. CI 가 Kubernetes 1.36 에서 돈다.
- 번들 구성요소: Istio 1.30.1, Knative 1.22.0, cert-manager 1.20.2, Pipelines 2.16.1, KServe 0.18.0, Trainer 2.2.0. 따로 고르지 않는다.
- 권장 자원은 RAM 16GB 이상, CPU 8코어. `example/kustomization.yaml` 에서 구성요소를 빼면 4~8GB 로도 가능하다. 이 PC(WSL 24GB)는 충분하다.

## 주의
- 커뮤니티는 연 2회(26.03, 26.10) 릴리스하고 각 릴리스를 약 6개월 best-effort 로 지원한다. 26.03 은 2026-03-22 출시라 **지원 기간이 끝났을 수 있다.** 26.10 이 나왔는지는 확인하지 못했다.
- Katib/Notebooks 의 정확한 버전은 확인하지 못했다. 설치 시 매니페스트를 직접 열어 확인한다.
- 설치할 구성요소(Pipelines, Notebooks, KServe, Katib 등)는 05 kind 단계 이후에 정한다.

## 재검토 시점
26.10 확인 시 (설치 전에 먼저 본다). 설치 후에는 지원 종료 시점.

## 출처 (확인 2026-10-23)
- https://github.com/kubeflow/community-distribution/releases
- https://github.com/kubeflow/community-distribution (Prerequisites, 릴리스 주기)
- https://blog.kubeflow.org/kubeflow-1.11-release/
