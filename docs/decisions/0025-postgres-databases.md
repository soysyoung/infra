# 0025. 실습용 DB knowledge_lab (소유자 notebook_rw)

- 상태: **적용, 부분 검증** (2026-11-26). 사용자가 `10-4` 와 `verify/10-4` 를 실행해 통과했다. 아래 '적용 결과' 와 '미검증'. [ADR 0022](0022-notebook-postgres-access.md) 의 "notebook_rw 는 DDL 불가" 를 이 DB 에 한해 보완한다 (대체하지 않는다).

## 상황
예제 코드가 `.env` 의 `RAG_SCHEMA=d26_rag` 스키마를 직접 만든다. guest 네임스페이스의 Notebook 은 `notebook_rw` 로 접속하는데 이 계정은 `app` DB 에 `CREATE` 권한이 없고 `public` 스키마에는 `USAGE` 만 있어 권한 오류가 난다 (사용자가 받은 안내문). 소유자 `app` 을 guest 에 주는 것은 0022 가 막은 일이다. user 네임스페이스는 `app` 이 들어가므로 같은 오류가 나지 않는다.

## 검토한 것
- **`postgres` 계정을 새로 만든다 (사용자 요청):** `postgres` 는 클러스터를 만들 때 이미 있는 superuser 다 (실측 2026-11-23, `pg_roles`: `rolsuper=t`, `rolcanlogin=t`). 같은 이름의 비-superuser 역할은 만들 수 없을 것으로 본다 (시험하지 않았다). 외부에서 쓰려면 Cluster 의 `enableSuperuserAccess` 를 켜고 비밀번호 Secret 을 만들어야 하는데, [ADR 0024](0024-postgres-pgvector.md) 가 인용한 CloudNativePG 권고(기본 끄기)와 어긋나고 예제에 superuser 는 필요 없다.
- **별도 계정 `practice` (사용자 요청):** 취소했다. 새 계정과 비밀번호를 늘리지 않는다.
- **`app` DB 에 스키마만 미리 만든다:** 안에 테이블을 만드는 단계에서 같은 오류가 날 것이라 부족하다.
- **`app` 소유로 두고 `notebook_rw` 에 `GRANT CREATE ON DATABASE`:** 처음 제안한 안이다. 사용자가 소유자를 `notebook_rw` 로 하자고 해서 바꿨다. 소유자는 그 DB 의 모든 권한을 가지므로 따로 부여할 것이 없다.

## 결정 (2026-11-23 사용자 결정)
- **`Database` 리소스로 `knowledge_lab` 을 만든다** (`k8s/postgres-databases.yaml`): `spec.owner: notebook_rw`, 확장 `vector`, 삭제 시 DB 를 남기는 `retain`. 10-3 과 같은 방식이다. `vector` 는 `d26_rag` 라는 이름으로 보아 RAG 예제일 것으로 짐작해 켰고, 예제가 pgvector 를 쓰는지는 확인하지 못했다.
- **`report_agent_lab` 도 같은 방식으로 만든다 (2026-11-26 사용자 요청).** 같은 yaml 에 `Database` 리소스(`postgres-database-report-agent-lab`)를 하나 더 두고 소유자 `notebook_rw`, 확장 `vector` 도 같다. `vector` 는 이 DB 가 쓰는지 몰라 `knowledge_lab` 과 맞췄다. 이 문서의 나머지 내용(한계, 미검증)은 두 DB 모두에 적용된다. 그래서 파일 이름에서 `lab` 을 뺐다 (`10-4-postgres-databases.sh`, `k8s/postgres-databases.yaml`, 이 문서). 쿠버네티스 리소스 이름(`postgres-database-knowledge-lab` 등)은 그대로다.
- **DB 목록은 yaml 에서만 관리한다 (2026-11-26 사용자 결정).** `10-4` 와 `verify/10-4` 는 yaml 의 `spec.name` 을 읽어 목록을 만들고 `teardown/10-4` 는 `kubectl delete -f` 로 지운다. DB 를 더하려면 `k8s/postgres-databases.yaml` 에 `Database` 를 붙이고 `10-4` 를 다시 실행한다. 리소스 이름은 `postgres-database-<DB 이름의 _ 를 - 로>` 규칙을 지켜야 한다. 파싱은 들여쓰기 2칸 `name:` 줄 중 `postgres-database-` 로 시작하지 않는 것이라서 yaml 들여쓰기에 기대는 단순한 방식이다 (이 클러스터에서 시험하지 않았다).
- **스크립트는 `10-4`.** `Cluster` Ready 와 역할 `notebook_rw`(10-2)를 확인 → 매니페스트 적용 → `status.applied` 대기 → DB 소유자와 `has_database_privilege(..., 'CREATE')` 를 확인한다. 여러 번 실행해도 안전해야 한다. 별도 `GRANT` 는 하지 않는다.
- **`app` DB 는 그대로다.** `notebook_rw` 는 거기서 여전히 DDL 이 안 된다. verify 가 이를 확인한다.
- 비밀번호는 새로 만들지 않는다. 기존 `.env` 의 `POSTGRES_NOTEBOOK_PASSWORD` 를 그대로 쓴다.

## 알려진 한계, 범위 밖
- **소유자라서 `notebook_rw` 는 `knowledge_lab` 을 `DROP DATABASE` 할 수 있다고 본다** (PostgreSQL 에서 DB 소유자는 삭제 권한이 있다는 기억이고 이 문서에서 확인하지 않았다). guest 네임스페이스의 모든 Notebook 사용자가 이 DB 를 지울 수 있다. 이 DB 에 중요한 데이터를 두지 않는다. 막으려면 소유자를 `app` 으로 하고 `GRANT CREATE` 로 바꿔야 한다.
- **Notebook 에서 `knowledge_lab` 으로 인자 없이 접속하는 설정은 하지 않았다.** `PodDefault postgres-notebook` 은 `PGDATABASE=app` 이고 password file 한 줄도 DB 이름이 `app` 이라서(`scripts/10-2`) `knowledge_lab` 에 접속하면 libpq 가 그 줄에 맞지 않아 비밀번호를 못 찾을 것으로 본다 (시험하지 않았다). 쓰려면 DB 이름 자리를 `*` 로 바꾸고 `PGDATABASE` 를 정해야 한다. [todo.md](../todo.md) 에 후속으로 적는다.
- **`teardown/10-2` 가 막힐 수 있다.** 그 스크립트는 `DROP ROLE notebook_rw` 를 직접 실행하는데, PostgreSQL 은 소유한 객체(`knowledge_lab`)가 있는 역할은 지우지 못하는 것으로 알고 있다 (확인하지 않았다). `knowledge_lab` 을 먼저 지워야 한다 (`teardown/10-4` 는 리소스만 지우고 DB 는 남기므로 `drop database knowledge_lab` 을 직접 해야 한다). `teardown/10-2` 는 이 문서에서 고치지 않았다.
- `notebook_rw` 는 `pg_read_all_data`, `pg_write_all_data` 멤버라서 `knowledge_lab` 안의 다른 사람 테이블도 읽고 쓴다. 계정이 하나라 guest 사용자끼리 스키마를 구분하지 못한다. 계정 하나를 여럿이 공유하는 지금 구조의 한계다.
- `.env` 의 guest 비밀번호가 추측하기 쉬운 값이다 (이 결정과 무관, 따로 바꾸길 권한다). 바꾼 뒤 `10-2` 를 다시 실행하면 DB 에 반영되는지는 0022 에서 미검증이다.

## 미검증
- `Database` 리소스로 `app` 이 아닌 새 DB 를 만드는 동작과 `spec.owner` 에 `DatabaseRole` 이 만든 역할이 통하는지 (이 클러스터에서 처음).
- 역할 `notebook_rw` 가 `Database` 보다 먼저 있어야 한다는 순서 (10-2 가 선행이라 지금은 맞다).
- `notebook_rw` 가 `knowledge_lab` 에서 스키마와 테이블을 만들 수 있고 `app` 에서는 막히는지: `verify/10-4` 가 확인한다.
- `teardown/10-4` 뒤 DB 가 남는지 (`retain`).

## 적용 결과
2026-11-26 사용자 실행 (출력은 사용자가 붙여 준 것):
- `10-4`: `postgres-database-knowledge-lab` 은 `unchanged` (이미 적용돼 있었다. 이전 버전의 `10-4` 를 실행한 것으로 보이나 이 세션에서 확인하지 못했다), `postgres-database-report-agent-lab` 은 `created`. 두 리소스 모두 `condition met`(`status.applied`), 두 DB 모두 소유자 `notebook_rw` 와 `CREATE` 권한 확인.
- `verify/10-4` 통과 (`==> OK`): 두 DB 에 `vector 0.8.7` 설치, `notebook_rw` 가 각 DB 에서 스키마와 `vector(3)` 테이블을 만들고 넣고 `<->` 로 읽는다, `app` DB 에서는 스키마 생성이 거부된다. 그래서 `Database` 리소스로 `app` 이 아닌 새 DB 를 만들 수 있고 `spec.owner` 에 `DatabaseRole` 의 역할이 통한다는 것이 확인됐다. 이 두 `NOTICE: schema "verify_kl" does not exist, skipping` 줄은 시험 전 정리 단계의 정상 메시지다.
- 스키마 `verify_kl` 이 끝에 지워졌는지는 출력으로 확인하지 못했다.
