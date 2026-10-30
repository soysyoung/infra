#!/usr/bin/env bash
# 삭제 09-1. OpenSearch 릴리스와 PVC(색인 데이터), 비밀번호 Secret, 네임스페이스
#
# helm uninstall 은 PVC 를 지우지 않고, 남은 PVC 로 다시 설치하면 처음 관리자 비밀번호가 그대로 쓰인다 (공식 문서).
# .env 의 OPENSEARCH_ADMIN_PASSWORD 는 지우지 않는다 (직접 지운다). 삭제 05(클러스터 삭제)가 이 모두를 포함하므로
# 클러스터는 두고 OpenSearch 만 지울 때 쓴다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

confirm "OpenSearch 와 안의 색인 데이터(PVC)를 삭제합니다."
if type -P helm >/dev/null && docker info >/dev/null 2>&1 && kubectl get ns opensearch >/dev/null 2>&1; then
  run helm --kube-context "kind-$CLUSTER" uninstall opensearch -n opensearch --ignore-not-found
  run kubectl delete ns opensearch   # PVC 와 Secret 도 함께 지워진다
else
  log "클러스터나 네임스페이스가 없어서 OpenSearch 삭제는 건너뜁니다."
fi
log "완료"
