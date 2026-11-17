#!/usr/bin/env bash
# 삭제 10-1. PostgreSQL Cluster(PVC 의 데이터 포함), 연산자, CRD
#
# 네임스페이스 postgres 를 지우면 Cluster 와 PVC, Secret 이 함께 사라진다. 연산자 차트는 CRD 를 지우지 않으므로
# (차트 README) 직접 지운다. CRD 삭제는 모든 네임스페이스의 CNPG 리소스를 지우므로 이 클러스터에 다른 Cluster 가 없을 때만 쓴다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

confirm "PostgreSQL 과 안의 데이터(PVC), 연산자, CNPG CRD 를 삭제합니다."
if type -P helm >/dev/null && docker info >/dev/null 2>&1 && kubectl get ns >/dev/null 2>&1; then
  run kubectl delete ns postgres --ignore-not-found   # 연산자가 살아 있는 동안 지워야 Cluster 가 정리된다
  run helm --kube-context "kind-$CLUSTER" uninstall cnpg -n cnpg-system --ignore-not-found
  run kubectl delete ns cnpg-system --ignore-not-found
  for crd in $(kubectl get crd -o name | grep 'cnpg.io'); do run kubectl delete "$crd"; done
else
  log "클러스터가 없어서 PostgreSQL 삭제는 건너뜁니다."
fi
log "완료"
