#!/usr/bin/env bash
# 10-4 검증 (knowledge_lab, report_agent_lab 각각):
#   1) Database 리소스가 적용됨, 소유자 notebook_rw, 확장 vector 설치됨
#   2) notebook_rw 가 그 DB 에서 스키마와 vector 컬럼 테이블을 만들고 넣고 읽는다
#   3) notebook_rw 가 app DB 에서는 여전히 스키마를 못 만든다 (ADR 0022 의 'DDL 불가' 가 app 에는 그대로)
# 시험 스키마 verify_kl 은 끝에 지운다. 비밀번호는 명령줄이나 환경변수로 넘기지 않고 DB 파드 안 0600 password file 로 쓴다 (verify/10-2 와 같다).
# .env 에 POSTGRES_NOTEBOOK_PASSWORD 가 없으면 2), 3) 은 건너뛴다 (10-2 를 먼저).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=postgres
DB=databases.postgresql.cnpg.io
# DB 이름은 yaml 의 spec.name 에서 읽는다 (10-4 와 같은 규칙: 들여쓰기 2칸 'name:' 줄 중 postgres-database-* 를 뺀 것)
LABS=($(sed -n 's/^  name: //p' "$ROOT/k8s/postgres-databases.yaml" | tr -d '\r' | grep -v '^postgres-database-' || true))
[ "${#LABS[@]}" -gt 0 ] || die "k8s/postgres-databases.yaml 에서 DB 이름을 하나도 읽지 못했습니다."
env_get() { sed -n "s/^$1=//p" "$ROOT/.env" 2>/dev/null | tr -d '\r' | tail -1; }
esc() { printf '%s' "$1" | sed 's/[\\:]/\\&/g'; }   # password file 값 안의 ':' 와 '\' 이스케이프 (PostgreSQL 문서 32.16)
nb_pw=$(env_get POSTGRES_NOTEBOOK_PASSWORD)

kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
PF=/run/pgpass_verify_kl   # DB 파드의 / 는 읽기 전용이라 /run 을 쓴다
sup() { kubectl -n "$NS" exec "$POD" -c postgres -- psql -d "$1" -v ON_ERROR_STOP=1 -Atc "$2"; }
nb() { kubectl -n "$NS" exec "$POD" -c postgres -- env PGPASSFILE="$PF" psql -h postgres-rw -U notebook_rw -d "$1" -v ON_ERROR_STOP=1 -Atc "$2"; }
cleanup() {
  for lab in "${LABS[@]}"; do sup "$lab" 'drop schema if exists verify_kl cascade' >/dev/null 2>&1 || true; done
  kubectl -n "$NS" exec "$POD" -c postgres -- rm -f "$PF" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1)
for lab in "${LABS[@]}"; do
  res="postgres-database-${lab//_/-}"
  [ "$(kubectl -n "$NS" get "$DB" "$res" -o jsonpath='{.status.applied}' 2>/dev/null)" = true ] || die "Database $res 가 적용되지 않았습니다 (scripts/10-4-postgres-databases.sh)."
  owner=$(sup app "select pg_get_userbyid(datdba) from pg_database where datname='$lab'")
  [ "$owner" = notebook_rw ] || die "$lab 의 소유자가 notebook_rw 가 아닙니다 (받은 값: '$owner')."
  ver=$(sup "$lab" "select extversion from pg_extension where extname='vector'")
  [ -n "$ver" ] || die "$lab 에 확장 vector 가 없습니다."
  log "$lab 있음, 소유자 notebook_rw, vector $ver"
done

if [ -z "$nb_pw" ]; then
  log "주의: .env 에 POSTGRES_NOTEBOOK_PASSWORD 가 없어 notebook_rw 시험은 건너뜁니다 (10-2 를 먼저 실행)."
  log "OK (일부): DB 생성과 소유자 확인"
  exit 0
fi
# password file 의 DB 칸은 '*' 로 둬서 app 과 실습 DB 에 같은 줄이 쓰이게 한다
printf '%s\n' "postgres-rw:5432:*:notebook_rw:$(esc "$nb_pw")" | kubectl -n "$NS" exec -i "$POD" -c postgres -- sh -c "umask 077; cat > $PF"

# 2)
for lab in "${LABS[@]}"; do
  sup "$lab" 'drop schema if exists verify_kl cascade' >/dev/null   # 이전 실행이 남긴 것 정리
  nb "$lab" 'create schema verify_kl; create table verify_kl.t(id int primary key, v vector(3)); insert into verify_kl.t values (1, $$[1,2,3]$$)' >/dev/null \
    || die "notebook_rw 가 $lab 에서 스키마와 테이블을 만들지 못했습니다."
  [ "$(nb "$lab" 'select id from verify_kl.t order by v <-> $$[1,1,1]$$ limit 1')" = 1 ] || die "notebook_rw 가 $lab 에서 만든 테이블을 읽지 못했습니다."
  log "notebook_rw: $lab 에서 스키마, vector 테이블 생성과 읽기/쓰기 동작"
done

# 3)
if nb app 'create schema verify_kl_deny' >/dev/null 2>&1; then
  sup app 'drop schema if exists verify_kl_deny' >/dev/null
  die "notebook_rw 가 app 에 스키마를 만들었습니다 (막혀 있어야 합니다)."
fi
log "notebook_rw: app 에서는 스키마 생성이 거부됨"
log "OK: ${LABS[*]} 사용 가능"
