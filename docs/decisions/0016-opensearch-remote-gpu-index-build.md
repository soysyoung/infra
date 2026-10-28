# 0016. OpenSearch 원격 GPU 인덱스 빌드 조사 (go/no-go 실험 전)

- 상태: 기록 (2026-10-28). **결정이 아니다.** 켜지 않았고 MinIO 도 설치하지 않았다. 켤지는 todo 26번의 실험 결과로 정한다. 쿼터([ADR 0015](0015-profile-resource-quota.md))와는 별개의 주제다

## 상황
OpenSearch([ADR 0014](0014-opensearch-single-node.md))의 벡터 인덱스 빌드를 GPU 로 하는 선택지가 있는지 조사했다. 조사만 했고 적용하지 않았다.

## 조사한 것
출처: [Building vector indexes remotely using GPUs](https://docs.opensearch.org/latest/vector-search/remote-index-build/), [Vector search settings](https://docs.opensearch.org/latest/vector-search/settings/), [빌더 USER_GUIDE](https://github.com/opensearch-project/remote-vector-index-builder/blob/main/USER_GUIDE.md).
- **OpenSearch 파드에는 GPU 를 주지 않는다.** GPU 는 인덱스 **빌드**만 별도 서비스(remote vector index builder)에 맡기는 방식으로 쓰고(3.0 부터), 검색은 CPU 가 한다. 그래서 `opensearch` 네임스페이스에 GPU 쿼터를 두지 않는다.
- 켜는 순서: `knn.remote_index_build.enabled: true` -> S3 저장소 등록과 `knn.remote_index_build.repository` -> 빌더를 띄우고 `knn.remote_index_build.service.endpoint` 지정. 인증이 필요하면 키스토어에 `service.username`, `service.password`.
- 대상: **faiss `hnsw`** 만 (IVF, product quantization, lucene, NMSLIB 는 안 됨), 벡터 64차원 이상. 인덱스를 만들 때 이 조합을 골라야 나중에 GPU 빌드를 쓸 수 있다 (매핑은 워크로드 저장소 몫).
- 세그먼트가 `index.knn.remote_index_build.size.min`(기본 50mb) 이상일 때만 원격 빌드한다. 우리 데이터는 전체 약 161MB 라 대량 적재 뒤 force merge 하면 대상이 된다 (추정). 빌드가 `client.timeout`(기본 60m) 안에 안 끝나면 CPU 로 만든다.
- 빌더는 Docker 컨테이너(`docker run --gpus all -p 80:1025 opensearchstaging/remote-vector-index-builder:api-latest`) 하나다. 쿠버네티스에서는 `nvidia.com/gpu: 1` 과 GPU 노드 toleration 을 가진 Deployment 로 띄우면 된다 (미시험).
- **미확인:** (1) 저장소가 Amazon S3 만 지원한다고 적혀 있고 MinIO 같은 S3 호환 저장소가 되는지, 엔드포인트를 지정할 수 있는지 문서에서 찾지 못했다 (빌더 소스는 읽지 않았다). (2) 빌더가 쓰는 VRAM 은 문서에 없다. 켤 때 `nvidia-smi` 로 잰다 (빌더 DEVELOPER_GUIDE 에 메모리 프로파일링 절차가 있다). (3) 고정 버전 태그를 찾지 못했다 (`api-latest` 만 확인). 켤 때 digest 로 고정한다. (4) 이 규모에서 GPU 빌드가 CPU 보다 빠른지.
- 결정: 지금은 켜지 않고 MinIO 도 설치하지 않는다. 켜는 조건과 실험은 todo 26번.


## 근거의 수준 (중요)
- 위 출처는 모두 **`latest` 문서와 빌더 저장소의 `main`** 이다. 우리가 고정한 **OpenSearch 3.8.0 이 원격 인덱스 빌드를 지원하는지는 확인하지 못했다 (미검증).** 3.8.0 버전 태그의 문서나 릴리스 노트는 읽지 않았다.
- 요구 사항(3.0 부터, faiss `hnsw`, 64차원 이상 등)도 `latest` 기준이다. 3.8.0 에서 같은지는 미확인이다.

## 비용
- **GPU 조각 1개를 점유한다.** 빌더 Deployment 는 `nvidia.com/gpu: 1` 을 요청하므로 time-slicing 으로 광고한 4개 중 1개를 쓴다. 그래서 [ADR 0015](0015-profile-resource-quota.md) 의 `quotas.env` 에서 `QUOTA_GPU_RESERVED=1` 로 프로필 배분 밖에 비워 둔다 (기본 사용자 3 + 두 번째 사용자 0 + 예약 1 = 4). 이 예약은 쿼터로 걸리지 않는다. `opensearch` 네임스페이스에는 쿼터를 두지 않는다.
- **VRAM 은 나뉘지 않는다** ([ADR 0013](0013-gpu-time-slicing.md)). 빌드 중 VRAM 사용량이 다른 GPU 파드(Notebook 등)의 OOM 위험이 된다. 사용량을 모른다 (위 미확인 2).
- 빌더 Deployment, S3 호환 저장소(MinIO) 설치와 운영, 메모리 추가. 메모리는 측정하지 않았다.
- 이득은 불확실하다: 데이터가 약 161MB 규모라 CPU 빌드보다 빠른지 모른다 (위 미확인 4).

## 다음
todo 26번: 켜기 전에 (1) 빌더 소스에서 S3 커스텀 엔드포인트 지원, (2) 빌더 이미지 digest 고정, (3) 3.8.0 지원 여부 확인, (4) 빌드 중 `nvidia-smi` 로 VRAM 측정. 하나라도 안 되면 CPU 빌드로 둔다 (no-go).
