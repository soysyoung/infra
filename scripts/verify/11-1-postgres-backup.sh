#!/usr/bin/env bash
# 11-1 검증: 백업을 받고, 그 백업으로 실제로 복원해 본다 (받을 수 있다는 것과 복원된다는 것은 다르다).
#   1) DB app 에 시험 표 backup_canary(id=1, v='canary-<초>') 를 만든다
#   2) 11-1-postgres-backup.sh 를 임시 폴더로 실행한다 (실제 백업 폴더에는 이 시험 백업을 남기지 않는다)
#   3) 임시 DB verify_restore 를 만들고 그 덤프를 pg_restore 로 복원한다
#   4) 복원된 backup_canary 에서 같은 값이 읽히는지, 같은 표 수가 복원됐는지 본다
#   5) 임시 DB, 시험 표, 임시 폴더를 지운다 (실패해도 지운다)
# 실제 백업 파일이 있으면 마지막으로 sha256 이 맞는지도 본다 (읽기 전용).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=postgres
kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s >/dev/null
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
sql() { kubectl -n "$NS" exec "$POD" -c postgres -- psql -d "$1" -v ON_ERROR_STOP=1 -Atc "$2"; }

TMP=$(mktemp -d)
trap 'sql postgres "drop database if exists verify_restore" >/dev/null 2>&1 || true; sql app "drop table if exists backup_canary" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

val="canary-$(date +%s)"
sql app "drop table if exists backup_canary; create table backup_canary(id int primary key, v text); insert into backup_canary values (1, \$\$$val\$\$)" >/dev/null
src_tables=$(sql app "select count(*) from information_schema.tables where table_schema='public'")

BACKUP_DIR="$TMP" bash "$(dirname "$0")/../11-1-postgres-backup.sh" >/dev/null
dump=$(ls "$TMP"/postgres/app-*.dump 2>/dev/null | head -1)
[ -n "$dump" ] && [ -s "$dump" ] || die "백업 파일이 만들어지지 않았습니다."
(cd "$TMP/postgres" && sha256sum -c "$(basename "$dump").sha256" >/dev/null) || die "sha256 이 맞지 않습니다."
log "백업 파일 생성, sha256 일치 ($(du -h "$dump" | cut -f1))"

sql postgres "drop database if exists verify_restore; create database verify_restore" >/dev/null
kubectl -n "$NS" exec -i "$POD" -c postgres -- pg_restore -d verify_restore --no-owner --role=app --exit-on-error < "$dump"   # scripts/README.md '백업과 복원' 의 명령과 같다
got=$(sql verify_restore "select v from backup_canary where id=1")
[ "$got" = "$val" ] || die "복원된 값이 다릅니다 (기대 $val, 실제 '$got')."
owner=$(sql verify_restore "select tableowner from pg_tables where tablename='backup_canary'")
[ "$owner" = app ] || die "복원된 표의 소유자가 app 이 아닙니다 ('$owner'). --role=app 이 적용되지 않았습니다."
dst_tables=$(sql verify_restore "select count(*) from information_schema.tables where table_schema='public'")
[ "$dst_tables" = "$src_tables" ] || die "복원된 표 수가 다릅니다 (원본 $src_tables, 복원 $dst_tables)."
log "복원 확인: 시험 표의 값이 같고 표 $dst_tables 개가 모두 복원됨"

# 실제 백업 폴더가 있으면 sha256 만 확인한다
REAL=${BACKUP_DIR:-$ROOT/../backups/infra}/postgres
if ls "$REAL"/app-*.dump >/dev/null 2>&1; then
  (cd "$REAL" && sha256sum -c app-*.dump.sha256 >/dev/null) && log "실제 백업 $(ls "$REAL"/app-*.dump | wc -l)개의 sha256 일치" || die "실제 백업 중 sha256 이 맞지 않는 파일이 있습니다."
else
  log "실제 백업 파일은 아직 없습니다 (scripts/11-1-postgres-backup.sh 를 실행하면 생깁니다)."
fi
log "OK"
