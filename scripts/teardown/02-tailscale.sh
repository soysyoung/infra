#!/usr/bin/env bash
# 삭제 02. Tailscale 연결 해제와 제거
#
# 주의: tailnet 으로 원격 접속 중이면 이 스크립트를 실행하는 순간 연결이 끊긴다.
# 관리 콘솔의 장치 목록에서 이 장치는 직접 삭제해야 한다 (https://login.tailscale.com/admin/machines).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

if ! dpkg -s tailscale >/dev/null 2>&1; then
  log "Tailscale 이 설치되어 있지 않아 건너뜁니다."; exit 0
fi
confirm "Tailscale 연결을 해제하고 제거합니다. tailnet 을 통한 원격 접속이 끊깁니다."

run sudo tailscale logout || true
run sudo systemctl disable --now tailscaled
run sudo apt-get purge -y tailscale
run sudo rm -rf /var/lib/tailscale /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg
log "완료. 관리 콘솔에서 이 장치를 직접 삭제하세요."
