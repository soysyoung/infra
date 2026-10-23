#!/usr/bin/env bash
# 02. Tailscale 설치 및 tailnet 가입 (WSL 안에서)
#
# 왜: 포트포워딩 없이 외부에서 이 서버에 SSH/kubectl 로 접근하기 위해.
# 하는 일: 설치 스크립트 실행 -> 'tailscale up --ssh' (브라우저 로그인 URL 출력)
#   --ssh : Tailscale SSH 사용. 별도 openssh-server 설정이 필요 없다.
#
# 선행: 01-wsl-systemd.sh 후 WSL 재시작
#
# 참고 (공식 문서):
#   - Linux 설치:  https://tailscale.com/docs/install/linux
#   - Tailscale SSH: https://tailscale.com/kb/1193/tailscale-ssh
#   - ACL(접근 제어): https://tailscale.com/kb/1018/acls
set -euo pipefail

if [ ! -d /run/systemd/system ]; then
  echo "systemd 가 실행 중이 아닙니다. 01-wsl-systemd.sh 와 'wsl --shutdown' 을 먼저 하세요." >&2
  exit 1
fi

if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo tailscale up --ssh

echo "tailnet IP: $(tailscale ip -4)"
