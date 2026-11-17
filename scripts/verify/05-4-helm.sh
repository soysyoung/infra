#!/usr/bin/env bash
# 05-4 검증: helm 이 versions.env 의 버전으로 설치됨
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

v=$(helm version --short 2>/dev/null || true)
log "helm: ${v:-없음}"
case "$v" in "${HELM_VERSION}"*) log "OK";; *) die "helm ${HELM_VERSION} 가 아닙니다.";; esac
