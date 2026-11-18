#!/usr/bin/env bash
# 10-3. PostgreSQL app 데이터베이스에 pgvector(vector 확장)를 켠다 (CloudNativePG Database 리소스, k8s/postgres-database-app.yaml)
#
# 왜: 이미지(system)에는 pgvector 가 들어 있지만 DB 에 CREATE EXTENSION 을 하기 전에는 쓸 수 없다. 설계와 근거는 docs/decisions/0024.
# 하는 일 (여러 번 실행해도 안전):
#   1) Cluster postgres 가 Ready 인지 확인
#   2) Database 리소스 postgres-database-app 을 적용하고 status.applied 가 true 가 될 때까지 기다린다
#   3) DB 에서 확장 vector 가 설치됐는지 확인한다
# 쓰는 법: app, notebook_rw 어느 계정이든 `vector(차원)` 컬럼과 `<->`(L2), `<=>`(코사인), `<#>`(내적) 연산자를 쓴다. 확장은 계정이 아니라 DB(app)에 설치된다.
# 확장 버전은 이미지의 기본 버전이다. 이미지를 올린 뒤 새 버전을 쓰려면 DB 에서 `ALTER EXTENSION vector UPDATE` 를 해야 한다 (이 스크립트는 하지 않는다).
#
# 선행: 10-1 (Cluster). 검증: scripts/verify/10-3-postgres-pgvector.sh
# 되돌리기: scripts/teardown/10-3-postgres-pgvector.sh (리소스만 지우고 확장은 남긴다)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=postgres
DB=databases.postgresql.cnpg.io   # 짧은 이름 database 가 다른 리소스와 겹치지 않게 전체 이름을 쓴다

kubectl -n "$NS" get cluster postgres >/dev/null 2>&1 || die "Cluster postgres 가 없습니다. scripts/10-1-postgres.sh 를 먼저 실행하세요."
kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s

kubectl apply -f "$ROOT/k8s/postgres-database-app.yaml"
kubectl -n "$NS" wait --for=jsonpath='{.status.applied}'=true "$DB/postgres-database-app" --timeout=120s \
  || die "Database 가 적용되지 않았습니다: $(kubectl -n "$NS" get "$DB" postgres-database-app -o jsonpath='{.status.message}' 2>/dev/null) (kubectl -n $NS describe $DB postgres-database-app)"

POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
ver=$(kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -Atc "select extversion from pg_extension where extname='vector'")
[ -n "$ver" ] || die "Database 는 적용됐는데 app 에 확장 vector 가 없습니다 (kubectl -n $NS describe $DB postgres-database-app)."
log "app 에 vector $ver 설치됨"
log "완료. 검증: scripts/verify/10-3-postgres-pgvector.sh"
