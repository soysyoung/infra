#!/usr/bin/env bash
# 삭제 05-4. helm 실행 파일과 캐시 (릴리스는 삭제 09 가 먼저 지운다)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

confirm "helm 을 삭제합니다."
run sudo rm -f /usr/local/bin/helm
run rm -rf "$HOME/.cache/helm" "$HOME/.config/helm"
log "완료"
