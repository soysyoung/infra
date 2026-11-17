#!/usr/bin/env bash
# 07-2 검증: NodePort 방식 (<tailnet 주소>:30080) 으로 Kubeflow 로그인 흐름이 응답하는가
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

login_flow_ok "$(tailscale ip -4):30080" \
  || die "NodePort 방식으로 접속할 수 없습니다 (07-2-nodeport.sh 실행 여부, 클러스터에 30080 포트 매핑이 있는지 'docker port $CLUSTER-control-plane' 로 확인)."

log "OK: NodePort 방식으로 Kubeflow 로그인 흐름(oauth2-proxy -> Dex)이 동작함"
