# 0021. PostgreSQL 단일 인스턴스 (CloudNativePG 연산자, Helm)

- 상태: 적용·검증 (2026-10-30). 사용자가 `10-1`, `verify/10-1` 을 실행해 통과했다. 아래 '미검증, 알려진 한계' 는 그대로 남아 있다

## 상황
OpenSearch(09)는 검색·벡터 인덱스이고 원본이 사라져도 다시 만들 수 있는 파생 데이터를 둔다 ([ADR 0014](0014-opensearch-single-node.md)). 트랜잭션과 정합성이 필요한 원본 데이터를 둘 관계형 DB 가 따로 필요하다. 모두 클러스터 안에서 쓴다.

## 선택지
1. Bitnami `postgresql` 차트: 무료 이미지가 2025년 하반기에 `bitnamilegacy` 로 옮겨졌다는 것을 기억하지만 지금(2026-10) 상태는 확인하지 못했다. 제외.
2. **CloudNativePG 연산자 (Helm) + Cluster 매니페스트**: 선택.
3. 공식 `postgres` 이미지 + 직접 만든 StatefulSet: Helm 으로 설치한다는 요구와 맞지 않고 백업, 복구를 직접 만들어야 한다.

## 공식 문서가 말하는 것 (2026-10-30 확인)
출처: [설치 문서](https://cloudnative-pg.io/docs/1.30/installation_upgrade/), [차트 README](https://github.com/cloudnative-pg/charts/blob/main/charts/cloudnative-pg/README.md), 차트 `Chart.yaml`, 연산자 `pkg/versions/versions.go` (release-1.30).
- 차트 `cnpg/cloudnative-pg` 0.29.1, appVersion 1.30.1, Kubernetes `>=1.29`. 저장소 `https://cloudnative-pg.github.io/charts`. 차트는 **연산자만** 설치하고, `Cluster` 는 companion `cluster` 차트나 직접 만든 매니페스트로 만든다.
- 연산자 배포 이름은 Helm 이면 `cnpg-cloudnative-pg`, 네임스페이스는 `cnpg-system`.
- `helm uninstall` 은 CRD 를 지우지 않는다. CRD 를 지우면 모든 `Cluster` 와 PVC 의 데이터가 함께 사라진다.
- 연산자 1.30.1 의 기본 이미지: `ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie`.
- 인스턴스가 1개일 때 연산자를 올리면 인스턴스가 재시작한다 (`primaryUpdateStrategy` 설명).

## 결정
- 연산자는 Helm 차트 0.29.1 (`versions.env` 의 `CNPG_CHART_VERSION`), PostgreSQL 이미지는 연산자 기본값을 그대로 **고정** (`POSTGRES_IMAGE`). 태그 대신 digest 고정은 하지 않았다.
- `Cluster` 는 `k8s/postgres-cluster.yaml` 한 개: 인스턴스 1, PVC 10Gi, 파드 requests = limits = 2Gi (Guaranteed), `shared_buffers` 512MB, DB `app`, 소유자 `app`. 비밀번호는 아래 '공식 기본값과 다른 점' 을 본다.
- 별도 네임스페이스: 연산자 `cnpg-system`, 데이터베이스 `postgres`. 프로필 ResourceQuota 대상이 아니다.
- 클러스터 안에서만 쓴다. Tailscale 노출은 만들지 않았다 (Dashboards 때의 `09-4` 같은 것). 필요하면 `kubectl port-forward svc/postgres-rw 5432:5432`.

## 공식 기본값과 다른 점: 앱 계정 비밀번호 (2026-10-30 결정)
- 공식 기본값: `initdb` 에 `secret` 을 주지 않으면 연산자가 슈퍼유저와 앱 계정의 **무작위 비밀번호**를 만들어 Secret 에 둔다. 직접 만든 비밀번호를 쓰는 방법도 공식 문서에 있다 (Secret 은 `kubernetes.io/basic-auth` 형식). 출처: [Bootstrap](https://cloudnative-pg.io/docs/1.30/bootstrap/).
- 이 저장소의 선택: `.env` 의 `POSTGRES_APP_PASSWORD` 로 `basic-auth` Secret `postgres-app-auth` 를 만들고 `bootstrap.initdb.secret.name` 으로 지정한다. 공식 문서가 허용하는 방식이지만 **권장 기본값은 아니다.** `.env` 를 쓰는 것은 이 저장소의 관례(OpenSearch `09-1` 도 같다)이고 CloudNativePG 문서에는 나오지 않는다.
- 이유: 이 저장소는 전체 삭제 후 재설치로 재현성을 증명한다 ([ADR 0010](0010-reboot-recovery.md)). 기본값은 재설치할 때마다 비밀번호가 바뀌어, 그 값을 쓰는 곳(Notebook, 앱)을 매번 고쳐야 한다. `.env` 에 두면 재설치해도 같은 값이다.
- 대가: 비밀번호가 `.env`(git 제외)와 Secret 두 곳에 있다. 비밀번호는 DB 를 처음 만들 때만 쓰이므로 `.env` 만 고쳐서는 바뀌지 않는다 (OpenSearch 와 같은 함정). 이미 초기화된 Cluster 의 비밀번호를 바꾸는 절차는 확인하지 않았다. 슈퍼유저 Secret 은 만들어지지 않았다 (아래 '적용 결과'). 관리용 접속은 파드 안 소켓으로 한다.

## 적용 결과 (2026-10-30, 사용자가 `10-1` 과 `verify/10-1` 을 실행하고 이어서 읽기 전용으로 확인)
- 연산자 배포 `cnpg-cloudnative-pg` 롤아웃 완료, `Cluster/postgres` Ready. 서버 PostgreSQL 18.6. 파드 `postgres-1` 1/1 Running, 재시작 0, CPU 워커(`mlops-worker2`)에 배치. PVC 10Gi `standard` Bound.
- `verify/10-1` 통과: 쓰기/읽기, `postgres-rw` 서비스로 `app` 계정(`.env` 의 비밀번호) 접속. `verify` 의 `psql` 소켓 접속과 첫 적용 때 웹훅 거부 여부는 문제 없었다 (재시도 로그 없음). 시험 테이블 `verify_pg` 는 지운다.
- `bootstrap.initdb.secret` 이 동작했다. 직접 만든 Secret 을 지정하면 **연산자가 만드는 `postgres-app` Secret 은 생기지 않는다.** Secret 은 `postgres-app-auth`(키는 `username`, `password` 뿐), `postgres-ca`, `postgres-replication`, `postgres-server` 이고 `uri`, `jdbc-uri` 키는 없어 접속 문자열은 직접 조립한다. `postgres-superuser` Secret 도 없다.
- 서비스 3개는 연산자가 자동으로 만든다: `postgres-rw`(selector `instanceRole=primary`, 쓰기와 읽기), `postgres-ro`(`instanceRole=replica`, 복제본만), `postgres-r`(`podRole=instance`, 모든 인스턴스). 인스턴스가 1개라 `ro` 는 가리킬 파드가 없을 것으로 추정한다 (selector 에서의 추론, 접속은 시험하지 않았다). 쓰는 쪽은 `postgres-rw` 로 한다.

## 공식 문서 재확인 (2026-10-30)
출처: [Bootstrap](https://cloudnative-pg.io/docs/1.30/bootstrap/), [Role management](https://cloudnative-pg.io/docs/1.30/declarative_role_management/), [Connecting from an application](https://cloudnative-pg.io/docs/1.30/applications/).
- initdb Secret 의 `username` 은 `owner` 와 같아야 한다 (우리는 둘 다 `app`).
- 다른 네임스페이스에서는 `postgres-rw.postgres` 로 접속한다. 기본 생성 `<cluster>-app` Secret 에는 `uri` 등이 있고 앱용이라고 쓰여 있으나, 직접 만든 Secret 을 쓰면 위처럼 생기지 않았다.
- 제한된 계정은 1.30 의 `DatabaseRole` 리소스가 권장 방식이다 (인라인 `managed.roles` 도 계속 지원). 리소스, 대상 `Cluster`, `passwordSecret` 이 **같은 네임스페이스**(`postgres`)에 있어야 하므로 Notebook 용으로는 사용자 네임스페이스에 Secret 사본이 따로 필요하다. 비밀번호 Secret 에 `cnpg.io/reload: "true"` 라벨을 붙이면 변경이 즉시 반영된다.
- 이미 있는 역할(`app` 포함)을 `DatabaseRole` 로 채택하면 명시하지 않은 속성이 기본값으로 덮어써지고 `inRoles` 에 없는 멤버십은 회수된다. `app` 은 `DatabaseRole` 로 관리하지 않는다. `ALTER ROLE` 로 직접 바꾼 내용은 다음 적용 때까지 감지되지 않는다.

## 미검증, 알려진 한계
- `app` 비밀번호를 설치 뒤에 바꾸면 반영되는지 (bootstrap 문서에 없고 시험하지 않았다), Notebook 파드에서 `postgres-rw.postgres:5432` 로 접속이 되는지 (Kubeflow 네트워크 정책 영향), 제한된 읽기 전용 역할에 `pg_read_all_data` 를 쓸 수 있는지 (PostgreSQL 기본 역할에 대한 기억일 뿐 확인하지 않았다).
- 메모리: 2Gi 가 OpenSearch(4Gi)와 Kubeflow 에 더해져 `.wslconfig` 24GB 안에 들어가는지 측정하지 않았다 (ADR 0014 에서는 설치 후 available 15GB).
- kind 의 PV 는 노드 컨테이너 안에 있어 클러스터를 지우면 데이터가 사라진다 (ADR 0014 와 같은 추정). 백업 경로(CNPG 의 Barman 오브젝트 스토어 백업 등)는 만들지 않았다. 원본 데이터를 두려면 먼저 정해야 한다.
- 단일 인스턴스라 고가용성이 없다. 연산자 업그레이드 때 짧게 끊긴다.
- 차트 릴리스 날짜를 확인하지 못해, 이 저장소의 "나온 지 2주 이상" 기준을 적용하지 않았다.
