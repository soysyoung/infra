#!/usr/bin/env bash
# 10-4. 실습용 데이터베이스 knowledge_lab, report_agent_lab 을 만든다. 소유자는 notebook_rw (k8s/postgres-databases.yaml)
#
# 왜: 예제가 스키마(RAG_SCHEMA=d26_rag)를 직접 만드는데 notebook_rw 는 app DB 에서 DDL 이 안 된다 (ADR 0022).
#   app 은 그대로 두고, 따로 만든 DB 에서만 notebook_rw 가 스키마와 테이블을 만들게 한다 (DB 소유자라서 CREATE 가 된다). 근거: docs/decisions/0025.
# 하는 일 (여러 번 실행해도 안전):
#   1) Cluster postgres 가 Ready 이고 역할 notebook_rw 가 있는지 확인 (없으면 10-2 를 먼저)
#   2) Database 리소스(DB 마다 하나)를 적용하고 status.applied 가 true 가 될 때까지 기다린다 (소유자 notebook_rw, 확장 vector)
#   3) DB 마다 소유자와 CREATE 권한이 맞는지 확인한다
# 쓰는 법: PGDATABASE=<DB 이름> 으로 접속한다. Notebook 의 PodDefault 는 아직 app 으로 고정이라 이 스크립트가 바꾸지 않는다.
#   notebook_rw 는 이 DB 들의 모든 테이블도 읽고 쓸 수 있고, 소유자라서 DB 를 지울 수도 있다.
# DB 를 더 만들려면 yaml 에 Database 리소스만 추가하고 이 스크립트를 다시 실행한다 (리소스 이름은 postgres-database-<DB 이름의 _ 를 - 로> 규칙을 지킨다). 목록은 yaml 에서 읽는다.
#
# 선행: 10-1 (Cluster), 10-2 (notebook_rw). 되돌리기: scripts/teardown/10-4-postgres-databases.sh (리소스만 지우고 DB 는 남는다)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=postgres
DB=databases.postgresql.cnpg.io
# DB 이름은 yaml 의 spec.name 에서 읽는다 (들여쓰기 2칸 'name:' 줄 중 리소스 이름 postgres-database-* 를 뺀 것). 그래서 DB 를 더하려면 yaml 만 고치면 된다.
LABS=($(sed -n 's/^  name: //p' "$ROOT/k8s/postgres-databases.yaml" | tr -d '\r' | grep -v '^postgres-database-' || true))
[ "${#LABS[@]}" -gt 0 ] || die "k8s/postgres-databases.yaml 에서 DB 이름을 하나도 읽지 못했습니다."

kubectl -n "$NS" get cluster postgres >/dev/null 2>&1 || die "Cluster postgres 가 없습니다. scripts/10-1-postgres.sh 를 먼저 실행하세요."
kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
sql() { kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -v ON_ERROR_STOP=1 -Atc "$1"; }

[ "$(sql "select count(*) from pg_roles where rolname='notebook_rw'")" = 1 ] || die "역할 notebook_rw 가 없습니다. scripts/10-2-postgres-notebook-access.sh 를 먼저 실행하세요."

kubectl apply -f "$ROOT/k8s/postgres-databases.yaml"
for lab in "${LABS[@]}"; do
  res="postgres-database-${lab//_/-}"
  kubectl -n "$NS" wait --for=jsonpath='{.status.applied}'=true "$DB/$res" --timeout=120s \
    || die "Database $res 가 적용되지 않았습니다: $(kubectl -n "$NS" get "$DB" "$res" -o jsonpath='{.status.message}' 2>/dev/null) (kubectl -n $NS describe $DB $res)"
  owner=$(sql "select pg_get_userbyid(datdba) from pg_database where datname='$lab'")
  [ "$owner" = notebook_rw ] || die "$lab 의 소유자가 notebook_rw 가 아닙니다 (받은 값: '$owner')."
  [ "$(sql "select has_database_privilege('notebook_rw', '$lab', 'CREATE')")" = t ] || die "notebook_rw 에게 $lab 의 CREATE 권한이 없습니다."
  log "$lab 있음, 소유자 notebook_rw, CREATE 권한 확인"
done
log "완료. PGDATABASE=<DB 이름> 으로 접속하세요. 검증: scripts/verify/10-4-postgres-databases.sh"
