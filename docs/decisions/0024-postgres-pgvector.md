# 0024. PostgreSQL 에서 pgvector 켜기 (CloudNativePG `Database` 리소스의 `spec.extensions`)

- 상태: **적용, 부분 검증** (2026-11-18). 사용자가 `10-3`, `verify/10-3`, 재실행, `teardown/10-3`, 재적용을 실행했고 모두 통과했다. 아래 '확인한 것' 중 '실측' 표시는 읽기 전용 조회 결과이고 나머지는 공식 문서를 읽은 것이다. 적용 결과는 '적용 결과' 절, 아직 시험하지 못한 것은 '미검증' 절.

## 상황
[ADR 0021](0021-postgres-cloudnativepg.md) 의 PostgreSQL(`ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie`)에서 벡터 컬럼과 유사도 검색(pgvector)을 쓰고 싶다. 현재 `app` 데이터베이스에는 확장이 설치되어 있지 않다.

## 확인한 것 (2026-11-18)
**실측 (읽기 전용 조회, `kubectl exec ... psql`)**
- `pg_available_extensions` 에 `vector` 기본 버전 `0.8.7` 이 있고 `installed_version` 은 비어 있다. 이미지에 패키지는 있고 `app` 에 아직 켜지지 않았다.

**공식 문서**
- 이미지: [cloudnative-pg/postgres-containers](https://github.com/cloudnative-pg/postgres-containers) README. `system` 은 `standard` 위에 Barman Cloud 를 얹은 이미지이고 `standard` 는 PGAudit, Postgres Failover Slots, pgvector, 전체 로캘, LLVM JIT 를 포함한다. 이미지를 바꿀 필요가 없다. (README 를 질의형으로 읽었고 전문을 읽은 것은 아니다.)
- 켜는 방법: [pgvector README](https://github.com/pgvector/pgvector). 확장을 쓸 데이터베이스마다 `CREATE EXTENSION vector;` 를 한 번 실행한다. 업그레이드는 `ALTER EXTENSION vector UPDATE;`.
- 권한: [PostgreSQL 18 CREATE EXTENSION](https://www.postgresql.org/docs/18/sql-createextension.html). 확장 설치는 보통 그 확장의 객체를 만들 권한(많은 경우 superuser)이 필요하고, 제어 파일에 `trusted` 로 표시된 확장만 DB 의 `CREATE` 권한이 있는 사용자가 설치할 수 있다. pgvector 의 [`vector.control`](https://github.com/pgvector/pgvector/blob/master/vector.control)(master)에는 `trusted` 가 없다. 따라서 `app` 계정으로 직접 `CREATE EXTENSION` 하면 거부될 것으로 읽힌다 (시험하지 않았다).
- 선언적 설치: [CloudNativePG 1.30 Database management](https://cloudnative-pg.io/docs/1.30/declarative_database_management/). `Database` 리소스의 `spec.extensions` 에 `name`(필수), `ensure`(기본 `present`), `version`, `schema` 를 적는다. 이 기능은 "확장 설치에 superuser 가 필요할 수 있고 CloudNativePG 는 superuser 접근을 기본적으로 끄기를 권장하므로" 있다고 문서에 적혀 있다. 내부적으로 `CREATE EXTENSION`, `DROP EXTENSION`, `ALTER EXTENSION`(`UPDATE TO` 와 `SET SCHEMA` 만)을 쓴다. `spec.extensions` 에 적은 것만 맞추고 나머지 확장은 건드리지 않는다.
- 기존 DB: 같은 문서의 "Creating vs. Altering a Database" 에 새 DB 는 `CREATE DATABASE`, 기존 DB 는 `ALTER DATABASE` 를 쓴다고 되어 있다. `initdb` 로 만든 `app` 에 적용할 수 있다고 읽힌다. 인코딩, 콜레이션 같은 불변 필드의 변경은 무시된다.
- 삭제: `databaseReclaimPolicy` 기본값은 `retain` (리소스를 지워도 DB 는 남는다). 한 번 적용된 뒤에는 `metadata.generation` 이 바뀔 때만 다시 적용되고 수동 변경을 덮어쓰지 않는다. 같은 DB 를 두 `Database` 리소스가 관리하면 두 번째가 거부된다.
- 제외한 방법: [Bootstrap](https://cloudnative-pg.io/docs/1.30/bootstrap/) 의 `postInitApplicationSQL` 은 "클러스터가 만들어진 직후 한 번만" superuser 로 실행되고, 오류가 나면 부트스트랩이 중단된다. 이미 돌고 있는 클러스터에는 맞지 않아 쓰지 않는다.

## 결정
- **`Database` 리소스로 `app` 에 `vector` 를 선언한다** (`k8s/postgres-database-app.yaml`: `spec.name: app`, `spec.owner: app`, `spec.cluster.name: postgres`, `spec.extensions: [{name: vector, ensure: present}]`, 네임스페이스 `postgres`). 이유: 공식 문서가 superuser 비밀번호를 우리가 다루지 않고 확장을 켜는 방법으로 제시한 방식이고, 10-2 의 `DatabaseRole` 과 같은 선언형이며, 이미 있는 클러스터에 적용된다.
- **새 단계 `10-3` 으로 만든다.** 10-1(클러스터), 10-2(Notebook 접속)처럼 목적 하나에 스크립트 하나와 `verify`, `teardown` 짝을 둔다. 10-1 은 고치지 않는다 (이미 통과한 단계의 의미를 바꾸지 않는다).
  - `scripts/10-3-postgres-pgvector.sh`: Cluster `postgres` 가 있는지 확인 → 매니페스트 적용 → `status.applied` 가 `true` 가 될 때까지 대기 → DB 에서 `installed_version` 확인. 여러 번 실행해도 안전해야 한다.
  - `scripts/verify/10-3-postgres-pgvector.sh`: `installed_version` 이 있다, `vector` 컬럼 테이블을 만들어 행을 넣고 `<->` 로 조회된다, 시험 테이블은 끝에 지운다. 계정은 `app` 과 `notebook_rw`(10-2) 둘 다 시험한다 (아래 미검증).
  - `scripts/teardown/10-3-postgres-pgvector.sh`: `Database` 리소스(`postgres-database-app`)만 지운다. **확장은 남긴다** (`retain`, 사용자 결정 2026-11-18). 10-2 의 teardown 처럼 클러스터를 지우면(teardown 10-1, 네임스페이스 `postgres` 삭제) 함께 사라지므로 `all.sh` 에는 넣지 않는다. 확장을 직접 지우려면 `drop extension vector` 를 따로 실행해야 하고, `vector` 컬럼이 있는 테이블이 있으면 실패하거나 컬럼이 영향을 받는다.
- 이미지, `postgres-cluster.yaml`, `versions.env` 는 바꾸지 않는다.

## 적용 결과 (2026-11-18, 사용자 실행, 출력은 [verify/README.md](../../scripts/verify/README.md) 마지막 절)
- `Database` 리소스가 `initdb` 로 만든 `app` 을 넘겨받아 `status.applied` 가 `true` 가 됐고 `vector 0.8.7` 이 설치됐다. `version` 을 적지 않아도 이미지의 기본 버전이 설치됐다.
- `verify/10-3` 통과: `app` 이 `vector(3)` 컬럼 테이블을 만들고 `<->` 로 가까운 행을 찾았고, `notebook_rw` 가 같은 테이블에 `vector` 값을 쓰고 `<->` 로 조회했다. 확장이 만든 타입과 연산자를 다른 계정이 쓸 수 있다는 것(기억이었다)이 실측으로 확인됐다.
- `10-3` 재실행은 `unchanged` 였다. `teardown/10-3` 은 `deleted` 로 끝났고 이어서 `10-3` 이 `created` 로 다시 만들어 `condition met`, `vector 0.8.7` 이었다. `kubectl wait --for=jsonpath` 가 동작했다.
- **`verify/10-3` 의 첫 실행은 실패했다.** 시험 테이블을 DB 파드 안 슈퍼유저로 만들어 `app` 이 `permission denied for table verify_vec` 을 받았다. 스크립트 버그였고 pgvector 와 무관하다 (같은 실행에서 설치 확인은 통과). 테이블을 `app` 이 만들도록 고친 뒤 통과했다. `verify/10-2` 는 읽는 쪽이 `pg_read_all_data` 멤버라 소유자와 상관없이 읽혀서 같은 가정이 통했던 것이다.

- **teardown 직후 조회 (2026-11-18, 사용자 실행).** `teardown/10-3` 을 실행하고 곧바로 조회했다: `kubectl get databases.postgresql.cnpg.io` 는 `No resources found`, DB 에서 `select extname, extversion, extnamespace::regnamespace from pg_extension where extname='vector'` 는 `vector|0.8.7|public`. 리소스를 지워도 확장은 DB 에 남고(`retain`), 확장은 스키마 `public` 에 설치된다. 이 뒤에는 `10-3` 으로 다시 적용하지 않은 상태다.
- **Notebook 에서 확인 (2026-11-18, 사용자 실행, 셀 출력).** guest 네임스페이스 Notebook(`PGUSER=notebook_rw`): `select current_user` → `('notebook_rw',)`, `select '[1,2,3]'::vector <-> '[1,1,1]'::vector` → `(2.23606797749979,)` (√5, L2 거리 맞음). 같은 Notebook 에서 `create table nb_vec_test(...)` 는 `InsufficientPrivilege: permission denied for schema public` 으로 거부됐다 (ADR 0022 의 'DDL 불가'가 Notebook 에서도 확인됨, `vector` 컬럼 때문이 아니다). user 네임스페이스 Notebook(`app`): 시험 테이블 `nb_vec_test` 를 만들고 지우는 순서를 실행했고 마지막 `select to_regclass('public.nb_vec_test')` 가 `(None,)` 이라 시험 테이블이 남지 않았다. **그 앞 단계의 출력(계정 `app`, 확장 조회, `<->` 정렬 결과)은 받지 못했다.** `notebook_rw` 로 `vector` 컬럼에 쓰고 조회하는 것은 Notebook 에서 하지 않았고 `verify/10-3` 의 DB 파드 안 시험으로만 확인했다. 코사인(`<=>`) 연산자는 Notebook 에서 확인하지 않았다.

## 미검증, 알려진 한계 (2026-11-18 적용 뒤에도 남은 것)
- `ALTER DATABASE` 에 다른 부작용이 없는지는 DB 설정을 전후로 비교하지 않았다 (적용과 `verify` 는 통과).
- CloudNativePG 가 `ensure: absent` 에서 `DROP EXTENSION` 에 `CASCADE` 를 쓰는지 (문서에 없음). teardown 에서 쓰지 않으므로 지금은 영향이 없다.
- `Database` 리소스가 `postgres` 네임스페이스와 함께 지워질 때 finalizer 로 막히지 않는지. teardown 10-1 은 연산자가 살아 있는 동안 네임스페이스를 지우므로 문제가 없을 것으로 보지만 시험하지 않았다. 전체 재설치 경로에서 `10-3` 도 시험하지 않았다.
- 문서의 "managed extensions"(`pg_stat_statements` 등)와 `Database` CRD 의 충돌 책임은 사용자에게 있다고 한다. 이 클러스터는 managed extension 을 쓰지 않는다 (`postgres-cluster.yaml` 에 해당 설정 없음).
- 백업(`11-1`)과 복원이 `vector` 컬럼과 확장을 포함하는지는 시험하지 않았다. 복원 대상 DB 에도 확장이 필요하다. 이 문서 범위 밖이지만 벡터 데이터가 쌓이기 전에 확인한다.
- 이 PC 에서 적용과 시험은 사용자가 실행한다.
