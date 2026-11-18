#!/usr/bin/env bash
# 삭제 10-3. Database 리소스 postgres-database-app 만 지운다
#
# 리소스는 retain(기본값)이라 지워도 DB app 과 확장 vector 는 그대로 남는다 (사용자 결정, docs/decisions/0024).
# 확장까지 지우려면 직접 한다: kubectl -n postgres exec <primary 파드> -c postgres -- psql -d app -c 'drop extension vector'
#   (vector 컬럼이 있는 테이블이 있으면 실패하거나 그 컬럼이 영향을 받는다. 지우기 전에 확인할 것)
# 클러스터를 지우면(teardown 10-1, 네임스페이스 postgres 삭제) 함께 사라지므로 all.sh 에는 넣지 않았다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

kubectl get ns postgres >/dev/null 2>&1 || { log "네임스페이스 postgres 가 없어 건너뜁니다."; exit 0; }
confirm "Database 리소스 postgres-database-app 을 삭제합니다 (DB app 과 확장 vector 는 남습니다)."
run kubectl -n postgres delete databases.postgresql.cnpg.io postgres-database-app --ignore-not-found
log "완료. 확장 vector 는 DB 에 남아 있습니다."
