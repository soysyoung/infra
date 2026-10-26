#!/usr/bin/env bash
# 07-1 검증: port-forward 방식 (<tailnet 주소>:8080) 으로 Kubeflow 로그인 흐름이 응답하는가
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

systemctl is-active --quiet kubeflow-port-forward || die "kubeflow-port-forward 서비스가 실행 중이 아닙니다 (systemctl status kubeflow-port-forward)."
login_flow_ok "$(tailscale ip -4):8080"   || die "port-forward 방식으로 접속할 수 없습니다 (07-1-port-forward.sh 실행 여부 확인)."

log "OK: port-forward 방식으로 Kubeflow 로그인 흐름(oauth2-proxy -> Dex)이 동작함"
