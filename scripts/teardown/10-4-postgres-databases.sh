#!/usr/bin/env bash
# 삭제 10-4. k8s/postgres-databases.yaml 에 있는 Database 리소스만 지운다 (지금은 knowledge_lab, report_agent_lab 용)
#
# 리소스는 retain(기본값)이라 지워도 DB knowledge_lab, report_agent_lab 과 그 안의 스키마, 테이블은 그대로 남는다 (docs/decisions/0025).
# DB 까지 지우려면 직접 한다: kubectl -n postgres exec <primary 파드> -c postgres -- psql -d app -c 'drop database <DB 이름>'
#   (접속 중인 세션이 있으면 실패한다. 안의 데이터가 모두 사라지니 지우기 전에 확인할 것)
# 클러스터를 지우면(teardown 10-1, 네임스페이스 postgres 삭제) 함께 사라지므로 all.sh 에는 넣지 않았다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

kubectl get ns postgres >/dev/null 2>&1 || { log "네임스페이스 postgres 가 없어 건너뜁니다."; exit 0; }
confirm "Database 리소스 postgres-database-knowledge-lab, postgres-database-report-agent-lab 을 삭제합니다 (DB 는 남습니다)."
run kubectl delete -f "$ROOT/k8s/postgres-databases.yaml" --ignore-not-found
log "완료. yaml 에 있던 DB 는 남아 있습니다."
