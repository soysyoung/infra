#!/usr/bin/env bash
# 삭제 10-2. 프로필 네임스페이스의 Secret/PodDefault postgres-notebook, DatabaseRole notebook-rw 와 DB 의 역할 notebook_rw
#
# 이미 떠 있는 Notebook 의 환경변수는 그대로 남는다 (재시작해야 사라진다). Cluster 와 데이터는 그대로 둔다.
# DatabaseRole 은 retain 이라 리소스를 지워도 역할이 DB 에 남으므로 DROP ROLE 을 직접 한다 (역할이 소유한 객체는 없다).
# 클러스터를 지우면(삭제 05) 함께 사라지므로 all.sh 에는 넣지 않았다. .env 의 POSTGRES_NOTEBOOK_* 는 지우지 않는다 (직접 지운다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

kubectl get ns default >/dev/null 2>&1 || { log "클러스터에 접속할 수 없어 건너뜁니다."; exit 0; }
confirm "Notebook 용 PostgreSQL Secret, PodDefault, 계정 notebook_rw 를 삭제합니다."
while read -r ns _; do
  kubectl get ns "$ns" >/dev/null 2>&1 || continue
  run kubectl -n "$ns" delete poddefault postgres-notebook --ignore-not-found
  run kubectl -n "$ns" delete secret postgres-notebook --ignore-not-found
done < <(quota_targets)

if kubectl get ns postgres >/dev/null 2>&1; then
  run kubectl -n postgres delete databaserole notebook-rw --ignore-not-found
  run kubectl -n postgres delete secret postgres-notebook-rw --ignore-not-found
  POD=$(kubectl -n postgres get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$POD" ]; then
    run kubectl -n postgres exec "$POD" -c postgres -- psql -d app -c 'drop role if exists notebook_rw'
  else
    log "primary 파드가 없어 DB 의 역할 삭제는 건너뜁니다."
  fi
fi
log "완료"
