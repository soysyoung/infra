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

# 서비스(postgres-rw)를 거친 TCP 접속. 비밀번호는 Secret(postgres-app-auth)에서 파드 안 환경변수로만 넘긴다.
pw=$(kubectl -n "$NS" get secret postgres-app-auth -o jsonpath='{.data.password}' | base64 -d)
kubectl -n "$NS" exec "$POD" -c postgres -- env PGPASSWORD="$pw" psql -h postgres-rw -U app -d app -Atc 'select 1' | grep -qx 1 \
  || die "postgres-rw 서비스로 app 계정 접속에 실패했습니다."
log "OK: postgres-rw 서비스에서 app 계정 접속 동작"
