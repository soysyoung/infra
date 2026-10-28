# 0014. OpenSearch 단일 노드 (Helm 공식 차트, k-NN)

- 상태: 적용·검증 (2026-10-28). `09`, `verify/09` 를 사용자가 실행해 통과했다. 실제 벡터 적재 뒤의 거동은 미시험

## 상황
워크로드가 벡터 약 10.5만 개 x 384차원(float32 기준 약 0.16GB, 그래프와 여유를 더해 약 0.2GB 로 본 값)을 k-NN 으로 검색해야 한다. 노드는 하나, replica 0, 힙 1~2GB, 파드 약 4Gi, PVC 수 GB 면 충분하다. 이 PC 의 WSL 은 24GB 이고 `vm.max_map_count` 는 이미 1048576 이다.

## 공식 문서가 말하는 것 (2026-10-28 확인)
출처: [Installing OpenSearch using Helm](https://docs.opensearch.org/latest/install-and-configure/install-opensearch/helm/), [Setting up a security demo configuration](https://docs.opensearch.org/latest/security/configuration/demo-configuration/), 차트 `values.yaml` (tag `opensearch-3.9.0`).
- 설치: `helm repo add opensearch https://opensearch-project.github.io/helm-charts/`, `helm install ... opensearch/opensearch -f values.yaml`. 기본은 3노드이며 차트에 `singleNode`, `replicas`, `opensearchJavaOpts`, `persistence.size`, `sysctlInit.enabled` 값이 있다.
- **OpenSearch 2.12 이후는 `OPENSEARCH_INITIAL_ADMIN_PASSWORD` 가 없으면 시작하지 않는다.** `extraEnvs` 로 넣는다. `extraEnvs` 키가 둘이면 마지막만 적용돼 파드가 반복 재시작한다 (Common issues).
- 비밀번호 요구: 8~100자, 대문자, 소문자, 숫자, 특수문자 각 1개 이상, zxcvbn 'strong' 이상, 사용자명 `admin` 과 비슷하지 않을 것. 문자 조건을 만족해도 zxcvbn 에서 거부될 수 있다.
- `helm uninstall` 은 PVC 를 지우지 않고, 남은 PVC 로 다시 설치하면 **처음 비밀번호가 그대로** 쓰인다.
- `vm.max_map_count` 는 262144 이상이어야 하고, 부족하면 `sysctlInit.enabled` 로 특권 init 컨테이너를 쓴다.

## 결정
- **Helm 차트 3.8.0** (OpenSearch 3.8.0), **Helm v4.2.4**. 기준은 Docker 때와 같다: 다음 마이너가 나온 지 2주 이상이면 직전 마이너의 마지막 패치. 3.9.0 은 한 달이라 3.8.0 을 택했다 (근거 표는 [versions.md](../versions.md)).
- 단일 노드: `singleNode: true`, `replicas: 1`, 힙 1GB, 파드 requests = limits = 4Gi (Guaranteed. 힙을 파드의 절반 이하로 잡아 나머지를 k-NN 네이티브 메모리와 파일 캐시에 둔다), PVC 10Gi.
- 보안 플러그인은 끄지 않는다 (https + 관리자 비밀번호). 비밀번호는 `.env` 의 `OPENSEARCH_ADMIN_PASSWORD` 에 두고, 없으면 `09` 가 만든다. 파드에는 Secret 의 `secretKeyRef` 로 넣어 Helm 릴리스 값에 평문이 남지 않게 했다.
- `sysctlInit` 은 끈다: 값이 이미 충분하고, 노드 컨테이너가 WSL 커널을 공유하므로 특권 컨테이너가 필요 없다.
- GPU 노드에는 taint 가 있어서 파드는 CPU 워커에 올라간다 (미시험).

## 적용 결과 (2026-10-28, 사용자가 `09`, `verify/09` 를 실행하고 이어서 읽기 전용으로 확인)
- 릴리스 `opensearch` 차트 3.8.0 / 앱 3.8.0 `deployed`, Helm v4.2.4. 파드 1/1 Running, 재시작 0, CPU 워커(`mlops-worker2`)에 배치 (GPU 노드 taint 로 피함).
- 클러스터 green, 노드 1개, 색인은 모두 replica 0. 플러그인에 `opensearch-knn` 이 있다 (기본 이미지에 포함).
- 반영된 값 확인: 파드 requests = limits = 4Gi, JVM 힙 최대 1073741824바이트(1GB), PVC 10Gi `standard` Bound.
- `.env` 에 `OPENSEARCH_ADMIN_PASSWORD` 가 만들어졌고, 무작위 비밀번호가 거부되지 않았다 (재시작 0).
- `verify/09` 가 통과했으므로 384차원 인덱스의 색인과 k-NN 검색이 동작한다. 출력은 받지 못했다.

## 메모리 예산 (`.wslconfig`)
WSL 안 `free -m` (전체 24030MB):

| 시점 | used | available |
|---|---|---|
| 설치 전 (Kubeflow 구동 중) | 7243MB | 16787MB |
| 설치 후 (OpenSearch, GPU Notebook 1개 포함) | 9021MB | 15009MB |

**`memory=24GB` 를 바꾸지 않는다.** 설치 후에도 available 이 15GB 남는다. 파드 안 OS 메모리는 4GB 중 약 37% 를 쓰고 있었다 (색인이 거의 비어 있는 상태). **미측정:** 실제 벡터를 넣은 뒤, GPU 파드 여러 개가 도는 부하 때의 값. `kubectl top` 은 metrics-server 가 없어 쓰지 못했다.

## 미검증
- 실제 벡터(약 10.5만 x 384차원) 적재 뒤의 메모리와 검색 지연.
- 파드 재시작과 WSL 재부팅 뒤 색인이 남는지.
- 차트 3.8.0 의 `values.yaml` 은 읽지 않고 3.9.0 의 것을 읽었다. 쓴 값(`singleNode`, 힙, 리소스, `persistence`)은 위 '적용 결과' 에서 반영된 것을 확인했고, 읽지 않은 다른 값은 모른다.
- kind 의 PV 는 노드 컨테이너 안에 있어 클러스터를 지우면 색인이 사라진다 (공식 동작이 아니라 kind 구조에서 온 추정). 장기 보관이 필요하면 원본 데이터에서 다시 색인한다.
- 전체 재설치 경로(`05-4` 부터 `09` 까지)에서 처음부터 도는지. 이번에는 이미 떠 있는 클러스터에 적용했다.
