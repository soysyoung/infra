# 0020. Notebook 에 OpenSearch guest-rw 접속 정보를 환경변수로 주입 (Secret + PodDefault)

- 상태: 적용 (2026-10-30). 사용자가 `09-5`, `verify/09-5` 를 실행했고, Notebook 에서 직접 접속을 확인했다 (아래 적용 결과). `verify/09-5` 출력은 받지 못했다

## 상황
Notebook 에서 OpenSearch 를 쓰려면 접속 정보가 필요하다. admin 비밀번호를 Notebook 에 두면 그 사용자(두 번째 사용자 포함)가 OpenSearch 전체 권한을 갖는다. [ADR 0018](0018-opensearch-guest-accounts.md) 의 `guest-rw`(temp-* 인덱스에만 쓰기·읽기)를 Notebook 에 넘긴다.

## 결정 (사용자 선택, 2026-10-30)
- **모든 사용자 네임스페이스**에 준다: 기본 사용자, `.env` 에 `EXTRA_USER_EMAIL` 이 있으면 두 번째 사용자 (06-4 의 `quota_targets` 와 같은 목록). 관리자 Notebook 에도 admin 이 아니라 guest-rw 를 준다. admin 이 필요한 작업은 Dashboards 나 터미널에서 직접 한다.
- 주입 방식은 **환경변수**: `OPENSEARCH_URL`(`https://opensearch-cluster-master.opensearch.svc:9200`), `OPENSEARCH_USER`, `OPENSEARCH_PASSWORD`. 06-3 의 `access-ml-pipeline` 과 같은 PodDefault 방식이다.
- 비밀번호는 PodDefault 에 쓰지 않고 네임스페이스마다 Secret `opensearch-guest`(키 `username`, `password`)에 둔다. PodDefault 는 `secretKeyRef` 로 읽는다. 값은 `.env` 의 `OPENSEARCH_GUEST_RW_*` 에서 온다.
- Notebook 을 만들 때 Configurations 에서 **'OpenSearch guest-rw 접속 정보'** 를 골라야 주입된다 (PodDefault 의 레이블 `opensearch-guest: "true"`). 이미 떠 있는 Notebook 에는 반영되지 않는다 (재시작).
- `09-5` 는 여러 번 실행해도 안전하다. 비밀번호를 바꾸면 `.env` 를 고치고 `09-3` 다음 `09-5` 를 실행한다.

## 한계와 주의
- 환경변수는 Notebook 안에서 누구나 읽을 수 있다 (`os.environ`). 그래서 admin 이 아니라 범위가 좁은 guest-rw 를 쓴다. guest-rw 는 `temp-*` 밖에서는 쓸 수 없으므로 실제 서비스 인덱스를 Notebook 에서 만들려면 `09-3` 의 `INDEX_PATTERN` 을 바꾸고 다시 실행해야 한다.
- OpenSearch 는 자체 서명 인증서를 쓴다. 클라이언트에서 인증서 검증을 끄거나(`verify_certs=False`) CA 를 지정해야 한다.
- 이 PodDefault 의 `OPENSEARCH_URL` 은 클러스터 안 주소라 Notebook 파드 안에서만 쓴다.

## 미검증 (적용 전)
- PodDefault 의 `env` 에 `valueFrom.secretKeyRef` 가 되는지 (스펙의 `env` 가 쿠버네티스 EnvVar 타입이라는 이해에 기댄다. 공식 문서로 이번에 확인하지 못했다). `verify/09-5` 가 서버 쪽 dry-run 으로 주입을 확인한다.
- **Notebook 파드(Istio 사이드카 포함)에서 `opensearch` 네임스페이스의 서비스에 닿는지.** 사이드카의 아웃바운드 정책이나 AuthorizationPolicy 때문에 막힐 수 있다. `verify/09-5` 는 실행 중인 Notebook 이 있을 때만 이를 시험한다. 막히면 원인을 조사해 이 문서에 기록한다.
- 서버 쪽 dry-run 이 PodDefault 웹훅을 거치는지 (거부되면 `verify/09-5` 가 그 단계를 건너뛴다).
- 두 번째 사용자 네임스페이스에서의 동작.

## 적용 결과 (2026-10-30)
- 사용자 보고: Notebook 을 만들 때 Configurations 에서 'OpenSearch guest-rw 접속 정보' 를 골라 환경변수를 주입하고, 셀에서 `requests` 로 `OPENSEARCH_URL` 에 guest-rw 로 요청했다. 응답은 `temp-test` 문서 쓰기(`PUT /temp-test/_doc/1?refresh=true`) 201, 검색 200, 인덱스 삭제 200, 범위 밖 인덱스 `/other-index/_search` 403 이었다.
- 따라서 환경변수 주입(PodDefault 의 `secretKeyRef`), Notebook 파드(Istio 사이드카 포함)에서 `opensearch` 네임스페이스로의 경로, guest-rw 의 `temp-*` 쓰기와 범위 제한이 기본 사용자 네임스페이스에서 확인됐다.
- 사용자 보고: 기본 사용자(admin)와 두 번째 사용자(guest) Notebook 계정 모두 OpenSearch 에 접속된다. guest 계정에서 같은 시험 셀을 실행한 응답도 쓰기 201, 읽기 200, 삭제 200, 범위 밖 403 이었다(사용자 확인).
- `verify/09-5` (사용자 실행): 두 네임스페이스 모두 Secret 이 `.env` 와 같고, 실행 중인 Notebook 파드에서 guest-rw 로 `/temp-*/_search` 가 200 이었다 ([verify/README.md](../../scripts/verify/README.md)). 서버 dry-run 주입 시험은 `kubectl apply` 의 `generateName` 제약으로 건너뛰어졌고(검증 스크립트의 버그), `kubectl create --dry-run=server` 로 고쳤다 (재실행은 안 했다). 건너뛰고도 `OK` 를 찍던 것도 실패로 바꿨다.
- 미확인: `GET /`(루트) 응답. 고친 dry-run 이 PodDefault 웹훅을 거쳐 환경변수 3개를 보여 주는지.
