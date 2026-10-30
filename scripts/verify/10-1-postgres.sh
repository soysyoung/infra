#!/usr/bin/env bash
# 10-1 검증: 연산자 Ready -> Cluster Ready -> 쓰기/읽기 (시험 테이블은 지운다) -> app 비밀번호로 서비스 접속
# psql 은 파드 안에서 실행한다 (소켓 접속이라 비밀번호가 필요 없고 명령줄에 나오지 않는다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=postgres
kubectl -n cnpg-system rollout status deploy/cnpg-cloudnative-pg --timeout=120s
kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=300s
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
log "primary 파드: $POD"
log "서버 버전: $(kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -Atc 'show server_version')"

sql() { kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -v ON_ERROR_STOP=1 -Atc "$1"; }
sql 'drop table if exists verify_pg; create table verify_pg(id int primary key, v text); insert into verify_pg values (1, $$ok$$)' >/dev/null
[ "$(sql 'select v from verify_pg where id=1')" = ok ] || die "쓴 값을 읽지 못했습니다."
sql 'drop table verify_pg' >/dev/null
log "쓰기/읽기: 동작"

# 서비스(postgres-rw)를 거친 TCP 접속. PostgreSQL 공식 문서는 PGPASSWORD 를 권하지 않으므로 password file 을 쓴다:
# 표준입력으로 DB 파드 안 /run 에 0600 파일을 만들고(비밀번호가 명령줄에 나오지 않는다) PGPASSFILE 로 가리킨 뒤 지운다.
pf=/run/pgpass_verify
trap 'kubectl -n "$NS" exec "$POD" -c postgres -- rm -f "$pf" >/dev/null 2>&1 || true' EXIT
pw=$(kubectl -n "$NS" get secret postgres-app-auth -o jsonpath='{.data.password}' | base64 -d)
printf '%s\n' "postgres-rw:5432:app:app:$(printf '%s' "$pw" | sed 's/[\\:]/\\&/g')" \
  | kubectl -n "$NS" exec -i "$POD" -c postgres -- sh -c "umask 077; cat > $pf"
kubectl -n "$NS" exec "$POD" -c postgres -- env PGPASSFILE="$pf" psql -h postgres-rw -U app -d app -Atc 'select 1' | grep -qx 1 \
  || die "postgres-rw 서비스로 app 계정 접속에 실패했습니다."
log "OK: postgres-rw 서비스에서 app 계정 접속 동작"
