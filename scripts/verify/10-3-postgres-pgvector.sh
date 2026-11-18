#!/usr/bin/env bash
# 10-3 검증:
#   1) Database 리소스 postgres-database-app 이 적용됨 (status.applied)
#   2) app 에 확장 vector 가 설치됨 (버전 출력)
#   3) postgres-rw 서비스로 app 계정이 vector 컬럼 테이블을 만들고 넣고 `<->` 로 가까운 행을 찾는다
#   4) notebook_rw (10-2)가 같은 테이블을 `<->` 로 조회하고 vector 값을 쓴다 (테이블 생성은 10-2 결정대로 막혀 있다). .env 에 비밀번호가 없으면 이 항목만 건너뛴다
# 시험 테이블 verify_vec 은 끝에 지운다. 비밀번호는 명령줄이나 환경변수로 넘기지 않고 DB 파드 안 0600 password file 로 쓴다 (verify/10-2 와 같다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=postgres
DB=databases.postgresql.cnpg.io
env_get() { sed -n "s/^$1=//p" "$ROOT/.env" 2>/dev/null | tr -d '\r' | tail -1; }
esc() { printf '%s' "$1" | sed 's/[\\:]/\\&/g'; }   # password file 값 안의 ':' 와 '\' 이스케이프 (PostgreSQL 문서 32.16)
app_pw=$(env_get POSTGRES_APP_PASSWORD)
[ -n "$app_pw" ] || die ".env 에 POSTGRES_APP_PASSWORD 가 없습니다 (scripts/10-1-postgres.sh)."
nb_pw=$(env_get POSTGRES_NOTEBOOK_PASSWORD)

kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
PF_APP=/run/pgpass_verify_vec_app; PF_NB=/run/pgpass_verify_vec_nb   # DB 파드의 / 는 읽기 전용이라 /run 을 쓴다
sup() { kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -v ON_ERROR_STOP=1 -Atc "$1"; }
as() { kubectl -n "$NS" exec "$POD" -c postgres -- env PGPASSFILE="$2" psql -h postgres-rw -U "$1" -d app -v ON_ERROR_STOP=1 -Atc "$3"; }
trap 'sup "drop table if exists verify_vec" >/dev/null 2>&1 || true; kubectl -n "$NS" exec "$POD" -c postgres -- rm -f "$PF_APP" "$PF_NB" >/dev/null 2>&1 || true' EXIT
putfile() { printf '%s\n' "postgres-rw:5432:app:$1:$(esc "$2")" | kubectl -n "$NS" exec -i "$POD" -c postgres -- sh -c "umask 077; cat > $3"; }
putfile app "$app_pw" "$PF_APP"

# 1), 2)
[ "$(kubectl -n "$NS" get "$DB" postgres-database-app -o jsonpath='{.status.applied}' 2>/dev/null)" = true ] || die "Database postgres-database-app 이 적용되지 않았습니다 (scripts/10-3-postgres-pgvector.sh)."
ver=$(sup "select extversion from pg_extension where extname='vector'")
[ -n "$ver" ] || die "app 에 확장 vector 가 없습니다."
log "Database 적용됨, app 에 vector $ver"

# 3) app: 생성, 삽입, 거리순 조회 ([1,2,3] 이 [1,1,1] 에 가장 가깝다)
sup 'drop table if exists verify_vec' >/dev/null   # 이전 실행이 남긴 것 정리 (슈퍼유저 소유일 수 있어 슈퍼유저로 지운다)
as app "$PF_APP" 'create table verify_vec(id int primary key, v vector(3)); insert into verify_vec values (1, $$[1,2,3]$$), (2, $$[4,5,6]$$)' >/dev/null || die "app 이 vector 컬럼 테이블을 만들지 못했습니다."   # app 이 만들어야 app 이 소유자로 쓸 수 있다
[ "$(as app "$PF_APP" 'select id from verify_vec order by v <-> $$[1,1,1]$$ limit 1')" = 1 ] || die "app 의 '<->' 거리순 조회가 기대와 다릅니다."
log "app: vector 컬럼 테이블 생성, 삽입, '<->' 거리순 조회 동작"

# 4) notebook_rw: 같은 테이블 조회, vector 값 쓰기 ([1,1,1] 을 넣으면 그 행이 가장 가깝다)
if [ -n "$nb_pw" ]; then
  putfile notebook_rw "$nb_pw" "$PF_NB"
  as notebook_rw "$PF_NB" 'insert into verify_vec values (3, $$[1,1,1]$$)' >/dev/null || die "notebook_rw 가 vector 값을 쓰지 못했습니다."
  [ "$(as notebook_rw "$PF_NB" 'select id from verify_vec order by v <-> $$[1,1,1]$$ limit 1')" = 3 ] || die "notebook_rw 의 '<->' 거리순 조회가 기대와 다릅니다."
  log "notebook_rw: vector 값 쓰기와 '<->' 조회 동작"
else
  log "주의: .env 에 POSTGRES_NOTEBOOK_PASSWORD 가 없어 notebook_rw 시험은 건너뜁니다 (10-2 를 먼저 실행)."
fi
log "OK: pgvector 사용 가능"
