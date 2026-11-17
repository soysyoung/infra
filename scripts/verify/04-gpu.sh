#!/usr/bin/env bash
# 04 검증: 컨테이너 안에서 GPU 가 보이는가
# kind 확정 전의 첫 관문. 실패하면 docs/decisions/0002 의 k3s 대안을 검토한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

docker run --rm --gpus all "$CUDA_TEST_IMAGE" nvidia-smi
log "OK: 컨테이너에서 GPU 확인"
