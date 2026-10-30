# 0022. Notebook 에서 PostgreSQL 접속 (읽기/쓰기 전용 계정 notebook_rw, 환경변수 주입)

- 상태: 작성만 함 (2026-10-30). `10-2` 스크립트 3개와 매니페스트 2개를 만들고 문법만 확인했다. 이 PC 에서 실행하지 않았다. 아래 '공식 문서가 말한 것' 이외의 동작은 모두 미검증

## 상황
[ADR 0021](0021-postgres-cloudnativepg.md) 로 PostgreSQL 이 클러스터 안에 있다. Notebook 에서 이 DB 를 쓰고 싶다. 요구(사용자, 2026-10-30): **읽기/쓰기, DB 전체, 기본 사용자와 공유용(guest) 계정의 Notebook 모두.** OpenSearch 는 [ADR 0020](0020-notebook-opensearch-guest-env.md) 에서 제한된 계정 guest-rw 를 Secret 과 PodDefault 로 주입했다. 같은 방식을 쓴다.

## 결정
- **소유자 `app` 을 주입하지 않고 별도 계정 `notebook_rw` 를 만든다.** `app` 은 테이블을 만들고 지우고 스키마를 바꿀 수 있는 소유자라서, 모든 Notebook(공유용 계정 포함)에 주입하면 DB 구조까지 지울 수 있다.
- `notebook_rw` 는 `pg_read_all_data` + `pg_write_all_data` 의 멤버다. 공식 문서([Predefined Roles](https://www.postgresql.org/docs/current/predefined-roles.html))에 따르면 이 역할은 모든 테이블, 뷰, 시퀀스에 대해 각각 SELECT, INSERT·UPDATE·DELETE 권한과 모든 스키마의 USAGE 를 준다. 행 수준 보안(RLS)은 우회하지 못한다. **DDL(테이블 생성, 삭제)은 안 된다.** 쓰기 역할만 있으면 UPDATE 의 조건을 읽지 못하므로 둘 다 필요하다.
- "DB 전체": `app` 데이터베이스의 모든 스키마와 테이블이다. 역할은 클러스터 전역 객체라서 같은 Cluster 의 다른 데이터베이스에도 접속을 시도할 수 있다 (PostgreSQL 의 기본 CONNECT 권한에 대한 기억이고 이 문서에서 확인하지 않았다). 지금 Cluster 에는 `app` 만 있다.
- 계정은 CloudNativePG 의 `DatabaseRole` 리소스([Role management](https://cloudnative-pg.io/docs/1.30/declarative_role_management/), 1.30 에서 권장)로 선언한다 (`k8s/postgres-notebook-role.yaml`). `passwordSecret` 은 `kubernetes.io/basic-auth` 이고 `cnpg.io/reload: "true"` 라벨을 붙이면 비밀번호 변경이 즉시 반영된다고 문서에 있다. 리소스, `Cluster`, Secret 은 같은 네임스페이스(`postgres`)여야 한다.
- 비밀번호는 `.env` 의 `POSTGRES_NOTEBOOK_PASSWORD` (없으면 `10-2` 가 만든다). ADR 0021 의 앱 계정과 같은 이유로 `.env` 를 쓴다.
- 주입은 `PodDefault postgres-notebook` (`k8s/postgres-notebook-poddefault.yaml`): Notebook 을 만들 때 Configurations 에서 'PostgreSQL 접속 정보 (notebook_rw)' 를 고른다. PostgreSQL 표준 환경변수 `PGHOST`(`postgres-rw.postgres.svc`), `PGPORT`, `PGDATABASE`(`app`), `PGUSER`, `PGPASSWORD` 가 들어가서 `psql` 과 `psycopg2` 가 인자 없이 접속한다. 접속 호스트는 `-rw` 서비스다 (쓰기가 있으므로, 서비스 설명은 ADR 0021).
- 대상 네임스페이스는 `09-5` 와 같다 (`quota_targets`): 기본 사용자, `.env` 에 `EXTRA_USER_EMAIL` 이 있으면 공유용(guest) 계정. Secret 은 네임스페이스 단위라서 각 네임스페이스에 사본을 만든다.
- `DatabaseRole` 의 삭제 정책은 `retain`(기본값)이다. `delete` 는 Cluster 와 같이 지워질 때 `DROP ROLE` 이 막혀 `Terminating` 에 걸릴 수 있다고 추정해 피했다 (미확인). 대신 `teardown/10-2` 가 `DROP ROLE` 을 직접 실행한다.

## 공식 문서가 말한 것과 말하지 않은 것 (2026-10-30 확인)
- 말한 것: 위 `DatabaseRole` 필드, `reload` 라벨, 같은 네임스페이스 제약, 다른 네임스페이스에서는 `서비스.네임스페이스` 로 접속, predefined role 의 권한.
- 말하지 않은 것(미검증): Kubeflow 프로필 네임스페이스의 Notebook 파드(Istio 사이드카 있음)에서 사이드카가 없는 `postgres` 네임스페이스로의 TCP 접속이 허용되는지. 네트워크 정책이나 Istio 정책이 막을 수 있다. 이것이 `verify/10-2` 의 4번이다.

## 미검증, 알려진 한계
- 스크립트와 매니페스트를 이 PC 에서 실행하지 않았다. `DatabaseRole` 이 실제로 DB 에 역할을 만드는지, `inRoles` 에 predefined role 이 통하는지, `verify/10-2` 의 판정이 맞는지 모두 첫 실행에서 알게 된다.
- Notebook 이미지에 `psycopg2` 가 있는지 모른다. 없으면 `verify/10-2` 는 TCP 연결까지만 확인하고 그렇다고 알린다. Notebook 에서는 `pip install psycopg2-binary` 가 필요할 수 있다.
- `.env` 의 비밀번호를 바꾼 뒤 `10-2` 를 다시 실행하면 DB 의 비밀번호가 따라 바뀌는지 시험하지 않았다. 이미 떠 있는 Notebook 은 재시작해야 새 환경변수를 받는다.
- 모든 테이블을 읽으므로 `app` 에 민감한 데이터가 들어오면 모든 Notebook 사용자가 읽는다. 공유용 계정 사용자도 포함이다. 지금은 `app` 이 비어 있다. 범위를 좁히려면 스키마나 테이블 단위 GRANT 로 바꿔야 한다 (이 문서 범위 밖).
- Notebook 의 모든 쿼리가 `postgres-rw`(primary)로 간다. 부하 분리는 하지 않았다.
