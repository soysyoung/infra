#!/usr/bin/env bash
# 03 검증: Docker 가 컨테이너를 실행하는가
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

docker run --rm hello-world >/dev/null
log "OK: docker $(docker --version)"
