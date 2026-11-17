#!/usr/bin/env bash
# 삭제 09-5. 프로필 네임스페이스의 Secret opensearch-guest 와 PodDefault opensearch-guest
#
# 이미 떠 있는 Notebook 의 환경변수는 그대로 남는다 (재시작해야 사라진다). OpenSearch 의 guest-rw 계정은 지우지 않는다 (09-3).
# 클러스터를 지우면(삭제 05) 함께 사라지므로 all.sh 에는 넣지 않았다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

kubectl get ns default >/dev/null 2>&1 || { log "클러스터에 접속할 수 없어 건너뜁니다."; exit 0; }
confirm "Notebook 용 OpenSearch Secret 과 PodDefault 를 삭제합니다."
while read -r ns _; do
  kubectl get ns "$ns" >/dev/null 2>&1 || continue
  run kubectl -n "$ns" delete poddefault opensearch-guest --ignore-not-found
  run kubectl -n "$ns" delete secret opensearch-guest --ignore-not-found
done < <(quota_targets)
log "완료"
