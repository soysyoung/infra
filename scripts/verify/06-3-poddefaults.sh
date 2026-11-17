#!/usr/bin/env bash
# 06-3 검증: PodDefault gpu-toleration, access-ml-pipeline 이 기본 사용자 네임스페이스에 있음
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=kubeflow-user-example-com
for pd in gpu-toleration access-ml-pipeline; do
  desc=$(kubectl -n "$NS" get poddefault "$pd" -o jsonpath='{.spec.desc}' 2>/dev/null) || die "PodDefault $pd 가 $NS 에 없습니다 (06-3-poddefaults.sh)."
  log "$pd: $desc"
done
log "OK"
