#!/usr/bin/env bash
# 01. WSL에서 systemd 활성화
#
# 왜: k3s, tailscaled 는 systemd 서비스로 실행된다. WSL 기본값은 systemd 꺼짐.
# 하는 일: /etc/wsl.conf 에 [boot] systemd=true 추가
#
# 참고 (공식 문서):
#   - WSL systemd 설정: https://learn.microsoft.com/en-us/windows/wsl/wsl-config#systemd-support
set -euo pipefail

CONF=/etc/wsl.conf

if grep -qs '^systemd=true' "$CONF"; then
  echo "이미 활성화됨: $CONF"
  exit 0
fi

# [boot] 섹션이 이미 있으면 중복 섹션을 만들지 않고 사람이 직접 고치게 한다.
if grep -qs '^\[boot\]' "$CONF"; then
  echo "[boot] 섹션이 이미 있습니다. $CONF 에 systemd=true 를 직접 추가하세요." >&2
  exit 1
fi

printf '[boot]\nsystemd=true\n' | sudo tee -a "$CONF" >/dev/null
echo "완료. Windows PowerShell에서 'wsl --shutdown' 실행 후 WSL을 다시 여세요."
