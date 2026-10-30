#!/usr/bin/env bash
# 삭제 09-2. OpenSearch Dashboards 릴리스와 계정 Secret (OpenSearch 와 색인은 그대로 둔다)
#
# teardown/09-1 이 네임스페이스째 지우므로 all.sh 에는 따로 넣지 않았다. Dashboards 만 지울 때 쓴다.
# Dashboards 의 설정(저장된 검색, 시각화)은 OpenSearch 의 .kibana 인덱스에 있어서 이 스크립트로는 지워지지 않는다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

confirm "OpenSearch Dashboards 를 삭제합니다 (OpenSearch 와 색인은 그대로)."
# port-forward 서비스(09-2 가 만든다)도 지운다. 접속할 곳이 없으면 5초마다 재시작만 반복한다.
unit=/etc/systemd/system/opensearch-dashboards-port-forward.service
if [ -f "$unit" ]; then
  run sudo systemctl disable --now opensearch-dashboards-port-forward
  run sudo rm -f "$unit"
  run sudo systemctl daemon-reload
fi
if type -P helm >/dev/null && docker info >/dev/null 2>&1 && kubectl get ns opensearch >/dev/null 2>&1; then
  run helm --kube-context "kind-$CLUSTER" uninstall opensearch-dashboards -n opensearch --ignore-not-found
  run kubectl -n opensearch delete secret opensearch-dashboards-account --ignore-not-found
else
  log "클러스터나 네임스페이스가 없어서 Dashboards 삭제는 건너뜁니다."
fi
log "완료"
