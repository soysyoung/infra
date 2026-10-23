#!/usr/bin/env bash
# 공통 함수. 각 스크립트에서 'source "$(dirname "$0")/lib/common.sh"' 로 읽는다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/versions.env"

log() { echo "==> $*"; }
die() { echo "오류: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null || die "$1 가 필요합니다. ${2:-}"; }

require_systemd() {
  [ -d /run/systemd/system ] || die "systemd 가 실행 중이 아닙니다. 01-wsl-systemd.sh 와 'wsl --shutdown' 을 먼저 하세요."
}
