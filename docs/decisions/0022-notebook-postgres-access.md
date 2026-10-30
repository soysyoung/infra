# 0022. Notebook 에서 PostgreSQL 접속 (읽기/쓰기 전용 계정 notebook_rw, 환경변수 주입)

- 상태: 적용, 부분 검증 (2026-10-30). 사용자가 `10-2`, `verify/10-2` 를 실행해 통과했다. PodDefault 를 골라 만든 Notebook 에서 환경변수 주입과 로그인을 확인했으나 **guest 계정(`notebook_rw`) 한 곳뿐이고 user 네임스페이스(`app`)는 확인하지 못했다.** 아래 '적용 결과' 와 '미검증'

## 상황
[ADR 0021](0021-postgres-cloudnativepg.md) 로 PostgreSQL 이 클러스터 안에 있다. Notebook 에서 이 DB 를 쓰고 싶다. 요구(사용자, 2026-10-30): **읽기/쓰기, DB 전체, 기본 사용자와 공유용(guest) 계정의 Notebook 모두.** OpenSearch 는 [ADR 0020](0020-notebook-opensearch-guest-env.md) 에서 제한된 계정 guest-rw 를 Secret 과 PodDefault 로 주입했다. 같은 방식을 쓴다.

## 결정
- **네임스페이스마다 주입하는 계정이 다르다 (2026-10-30 사용자 결정).** 기본 사용자 네임스페이스(`kubeflow-user-example-com`)에는 소유자 `app`(모든 권한)을, 공유용(guest) 네임스페이스에는 별도 계정 `notebook_rw` 를 준다. `app` 은 테이블을 만들고 지우고 스키마를 바꿀 수 있는 소유자라서 공유용 계정에는 주면 안 된다. 대가: 기본 사용자 네임스페이스의 모든 Notebook 은 DB 전체를 지울 수 있다. 처음 설계는 둘 다 `notebook_rw` 였고 같은 날 이렇게 바꿨다.
- `notebook_rw` 는 `pg_read_all_data` + `pg_write_all_data` 의 멤버다. 공식 문서([Predefined Roles](https://www.postgresql.org/docs/current/predefined-roles.html))에 따르면 이 역할은 모든 테이블, 뷰, 시퀀스에 대해 각각 SELECT, INSERT·UPDATE·DELETE 권한과 모든 스키마의 USAGE 를 준다. 행 수준 보안(RLS)은 우회하지 못한다. **DDL(테이블 생성, 삭제)은 안 된다.** 쓰기 역할만 있으면 UPDATE 의 조건을 읽지 못하므로 둘 다 필요하다.
- "DB 전체": `app` 데이터베이스의 모든 스키마와 테이블이다. 역할은 클러스터 전역 객체라서 같은 Cluster 의 다른 데이터베이스에도 접속을 시도할 수 있다 (PostgreSQL 의 기본 CONNECT 권한에 대한 기억이고 이 문서에서 확인하지 않았다). 지금 Cluster 에는 `app` 만 있다.
- 계정은 CloudNativePG 의 `DatabaseRole` 리소스([Role management](https://cloudnative-pg.io/docs/1.30/declarative_role_management/), 1.30 에서 권장)로 선언한다 (`k8s/postgres-notebook-role.yaml`). `passwordSecret` 은 `kubernetes.io/basic-auth` 이고 `cnpg.io/reload: "true"` 라벨을 붙이면 비밀번호 변경이 즉시 반영된다고 문서에 있다. 리소스, `Cluster`, Secret 은 같은 네임스페이스(`postgres`)여야 한다.
- 비밀번호는 `.env` 의 `POSTGRES_NOTEBOOK_PASSWORD` (없으면 `10-2` 가 만든다). ADR 0021 의 앱 계정과 같은 이유로 `.env` 를 쓴다.
- 주입은 `PodDefault postgres-notebook` (`k8s/postgres-notebook-poddefault.yaml`): Notebook 을 만들 때 Configurations 에서 'PostgreSQL 접속 정보' 를 고른다. 어느 계정이 들어가는지는 네임스페이스의 Secret `postgres-notebook` 이 정하므로 PodDefault 는 하나다. PostgreSQL 표준 환경변수 `PGHOST`(`postgres-rw.postgres.svc`), `PGPORT`, `PGDATABASE`(`app`), `PGUSER`, `PGPASSWORD` 가 들어가서 `psql` 과 `psycopg2` 가 인자 없이 접속한다. 접속 호스트는 `-rw` 서비스다 (쓰기가 있으므로, 서비스 설명은 ADR 0021).
- 대상 네임스페이스는 `09-5` 와 같다 (`quota_targets`): 기본 사용자, `.env` 에 `EXTRA_USER_EMAIL` 이 있으면 공유용(guest) 계정. Secret 은 네임스페이스 단위라서 각 네임스페이스에 사본을 만든다. 계정 선택은 `lib/quotas.sh` 의 `USER_PROFILE` 과 같은 네임스페이스면 `app`(비밀번호는 `.env` 의 `POSTGRES_APP_PASSWORD`), 아니면 `notebook_rw` 다. 이 구분은 "기본 사용자 네임스페이스 하나 + 그 밖"이라는 지금 구조에 맞춘 것이고, 사용자가 더 늘면 다시 정해야 한다.
- `DatabaseRole` 의 삭제 정책은 `retain`(기본값)이다. `delete` 는 Cluster 와 같이 지워질 때 `DROP ROLE` 이 막혀 `Terminating` 에 걸릴 수 있다고 추정해 피했다 (미확인). 대신 `teardown/10-2` 가 `DROP ROLE` 을 직접 실행한다.

## 공식 문서가 말한 것과 말하지 않은 것 (2026-10-30 확인)
- 말한 것: 위 `DatabaseRole` 필드, `reload` 라벨, 같은 네임스페이스 제약, 다른 네임스페이스에서는 `서비스.네임스페이스` 로 접속, predefined role 의 권한.
- 말하지 않은 것: Kubeflow 프로필 네임스페이스의 Notebook 파드(Istio 사이드카 있음)에서 사이드카가 없는 `postgres` 네임스페이스로의 TCP 접속이 허용되는지. 네트워크 정책이나 Istio 정책이 막을 수 있었다. 실행해서 확인했다 (아래 '적용 결과').

## 적용 결과 (2026-10-30, 사용자가 `10-2` 와 `verify/10-2` 를 실행, 출력은 [verify/README.md](../../scripts/verify/README.md))
- `DatabaseRole notebook-rw` 가 만들어지고 DB 에 역할 `notebook_rw` 가 생겼다 (로그인 가능, 슈퍼유저 아님, `pg_read_all_data`, `pg_write_all_data` 멤버). `postgres-rw` 서비스로 접속해 읽기/쓰기가 되고 테이블 생성은 거부됨을 `app` 이 만든 시험 테이블로 확인했다.
- 두 네임스페이스에 Secret 과 PodDefault 가 만들어졌다: `kubeflow-user-example-com` 은 `app`, `kubeflow-guest-example-com` 은 `notebook_rw`. 서버 쪽 dry-run 이 레이블을 단 파드에 환경변수 5개를 주입함을 보였다.
- **Notebook 파드(Istio 사이드카 있음)에서 `postgres-rw.postgres.svc:5432` 로 TCP 가 닿았다** (`test-01-0`, `test-guest-01-0`). 네트워크 정책이나 Istio 가 막지 않는다.
- 두 Notebook 모두 `psycopg2` 가 없어 TCP 까지만 확인했다. 이 Notebook 들은 PodDefault 없이 만든 것이라 환경변수가 들어 있지 않다. 계정과 비밀번호는 `verify` 가 표준입력으로 넘겼다.
- **PodDefault 로 만든 Notebook 에서 확인 (사용자 실행, 셀 출력).** 처음 시험한 Notebook 으로 `psycopg2.connect("")` 를 하면 `PGHOST` 가 비어 로컬 소켓 오류(`/var/run/postgresql/.s.PGSQL.5432`)로 실패했다. 파드 라벨과 env 이름을 읽기 전용으로 확인하니 `postgres-notebook` 라벨이 없고 `OPENSEARCH_*` 만 있었다 (PodDefault 를 고르지 않고 만든 Notebook). 'PostgreSQL 접속 정보' 를 골라 새로 만든 Notebook 에서는 `PGHOST=postgres-rw.postgres.svc`, `PGPORT=5432`, `PGDATABASE=app`, `PGUSER=notebook_rw` 가 들어 있었고 `pip install psycopg2-binary` 뒤 `select current_user` 가 `('notebook_rw',)` 를 돌려줬다. `PGUSER` 로 보아 guest 네임스페이스의 Notebook 이다 (사용자가 네임스페이스를 밝히지는 않았다).

## 미검증, 알려진 한계
- **user 네임스페이스(`app`)의 Notebook 에서의 환경변수와 로그인:** 확인하지 않았다. guest 쪽만 위 '적용 결과' 처럼 확인했다.
- 기본 Notebook 이미지(`/opt/conda`, Python 3.12)에는 `psycopg2` 가 없어 Notebook 마다 `pip install psycopg2-binary` 가 필요하다. 설치는 됐다. 이미지에 넣거나 영속 볼륨에 설치해 재생성 뒤에도 남기는 방법은 정하지 않았다 (Notebook 이 재생성되면 설치가 사라진다고 보지만 확인하지 않았다).
- `teardown/10-2` 는 실행하지 않았다. `DatabaseRole` 을 지워도 역할이 남는지(`retain`), `drop role` 이 되는지도 시험 전이다.
- `.env` 의 비밀번호를 바꾼 뒤 `10-2` 를 다시 실행하면 DB 의 비밀번호가 따라 바뀌는지 시험하지 않았다. 이미 떠 있는 Notebook 은 재시작해야 새 환경변수를 받는다.
- 모든 테이블을 읽으므로 `app` 에 민감한 데이터가 들어오면 모든 Notebook 사용자가 읽는다. 공유용 계정 사용자도 포함이다. 지금은 `app` 이 비어 있다. 범위를 좁히려면 스키마나 테이블 단위 GRANT 로 바꿔야 한다 (이 문서 범위 밖).
- Notebook 의 모든 쿼리가 `postgres-rw`(primary)로 간다. 부하 분리는 하지 않았다.
