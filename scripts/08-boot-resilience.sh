#!/usr/bin/env bash
# 08. 컨트롤 플레인 컨테이너가 kind 네트워크에서 떨어지거나 멈추면 스스로 복구하고, 8080 이 멈추면 port-forward 를 재시작하는 감시 서비스
#
# 왜: 2026-10-27 에 컨트롤 플레인 컨테이너가 kind 네트워크에서 떨어져 8080 이 막혔다 (docs/decisions/0010 '사고 기록').
#     그 원인 후보(API 서버를 tailnet 주소로 여는 것)는 05-1 이 127.0.0.1 로 바꿔서 구조적으로 없앴다. 그래도 컨테이너가 떨어지거나
#     멈추는 일이 다른 이유로 생길 수 있고, `kubectl port-forward` 가 연결이 끊긴 채 멈출 수도 있어서 마지막 안전망을 둔다.
# 하는 일 (1분마다 mlops-watchdog.timer 가 /usr/local/sbin/mlops-watchdog 를 실행):
#   a) 컨트롤 플레인이 kind 네트워크에서 빠졌거나 2번 연속 실행 중이 아니면: 모든 노드를 멈추고, 컨트롤 플레인을 원래 IP 로 다시 붙인 뒤,
#      컨트롤 플레인부터 시작하고 워커를 시작한다.
#   b) 127.0.0.1:8080 이 2번 연속 응답하지 않는데 API 서버(127.0.0.1:6443/livez)는 정상이면 kubeflow-port-forward 를 재시작한다.
# 여러 번 실행해도 안전하다. sudo 가 필요하다.
#
# 선행: 05-1, 06, 07-1 (컨트롤 플레인이 kind 네트워크에 붙어 실행 중이어야 한다)   검증: scripts/verify/08-boot-resilience.sh
# 주의: 일부러 docker stop 해 둔 클러스터도 다시 시작한다. 멈추려면 sudo systemctl stop mlops-watchdog.timer 부터 한다.
# shortcut: 컨트롤 플레인 IP 는 지금 값을 /etc/mlops/cp-ip 에 고정한다. 클러스터를 다시 만들면 이 스크립트를 다시 실행한다.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_systemd
require_cmd docker
systemctl cat kubeflow-port-forward >/dev/null 2>&1 || die "07-1-port-forward.sh 를 먼저 하세요."

CP=$CLUSTER-control-plane
CP_IP=$(docker inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "$CP" 2>/dev/null || true)
[ -n "$CP_IP" ] || die "$CP 가 kind 네트워크에 붙어 있지 않습니다. 먼저 컨트롤 플레인을 복구하세요 (docs/decisions/0010 '복구')."
log "컨트롤 플레인 IP: $CP_IP"

sudo install -d -m 755 /etc/mlops
echo "$CP_IP" | sudo tee /etc/mlops/cp-ip >/dev/null

sudo tee /usr/local/sbin/mlops-watchdog >/dev/null <<'EOF'
#!/usr/bin/env bash
# 1분마다 mlops-watchdog.timer 가 실행한다. 설치: scripts/08-boot-resilience.sh
set -u
CP=mlops-control-plane
NODES="mlops-worker mlops-worker2 mlops-worker3"
CP_IP=$(cat /etc/mlops/cp-ip)
FAILS=/run/mlops-watchdog.fails
DOWN=/run/mlops-watchdog.down
say() { echo "mlops-watchdog: $*"; }

systemctl is-active --quiet docker || { say "docker 가 실행 중이 아님, 건너뜀"; exit 0; }
docker inspect "$CP" >/dev/null 2>&1 || { say "$CP 컨테이너가 없음, 건너뜀"; exit 0; }

# (a) 컨트롤 플레인이 kind 네트워크에서 빠졌으면 같은 IP 로 다시 붙인다.
attached=$(docker inspect -f '{{if index .NetworkSettings.Networks "kind"}}yes{{end}}' "$CP")
# 붙어 있어도 실행 중이 아니면 센다. 고정 IP 를 다른 컨테이너가 먼저 가져가면 컨트롤 플레인은 시작에 실패한다 (Docker 문서).
# 2번 연속(약 2분)이면 복구한다.
if [ -n "$attached" ] && [ "$(docker inspect -f '{{.State.Status}}' "$CP")" != running ]; then
  n=$(( $(cat "$DOWN" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$DOWN"
  [ "$n" -ge 2 ] && attached="" || { say "$CP 가 실행 중이 아님 ($n/2), 다음 실행에서 다시 확인"; exit 0; }
fi
if [ -z "$attached" ]; then
  rm -f "$DOWN"
  say "컨트롤 플레인이 kind 네트워크에서 빠졌거나 멈춤 -> $CP_IP 로 다시 붙임"
  docker stop $NODES "$CP" >/dev/null 2>&1
  docker network disconnect -f kind "$CP" >/dev/null 2>&1
  docker network connect --ip "$CP_IP" kind "$CP" || { say "network connect 실패"; exit 1; }
  docker start "$CP" >/dev/null || { say "$CP 시작 실패"; exit 1; }
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 3
    ip=$(docker inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "$CP")
    [ "$(docker inspect -f '{{.State.Status}}' "$CP")" = running ] && [ "$ip" = "$CP_IP" ] && break
  done
  [ "${ip:-}" = "$CP_IP" ] || { say "$CP 가 $CP_IP 로 시작하지 못함 (docker logs $CP), 워커는 올리지 않음"; exit 1; }
  docker start $NODES >/dev/null
  say "복구 완료, 노드 시작함"
  exit 0
fi
rm -f "$DOWN"

# (b) 8080 이 응답하는지 본다. API 서버가 살아 있는데 2번 연속 응답이 없으면 port-forward 를 재시작한다.
code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:8080/oauth2/start || true)
if [ "$code" != 000 ]; then rm -f "$FAILS"; exit 0; fi
api=$(curl -sk -m 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:6443/livez || true)
[ "$api" = 200 ] || { say "8080 무응답, API 서버(livez)도 $api 라서 건너뜀"; exit 0; }
n=$(( $(cat "$FAILS" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAILS"
if [ "$n" -ge 2 ]; then
  say "8080 이 $n 번 연속 무응답 -> kubeflow-port-forward 재시작"
  systemctl restart kubeflow-port-forward
  rm -f "$FAILS"
fi
EOF
sudo chmod 755 /usr/local/sbin/mlops-watchdog

sudo tee /etc/systemd/system/mlops-watchdog.service >/dev/null <<'EOF'
[Unit]
Description=mlops 컨트롤 플레인 네트워크와 8080 응답을 확인하고 복구
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mlops-watchdog
EOF
sudo tee /etc/systemd/system/mlops-watchdog.timer >/dev/null <<'EOF'
[Unit]
Description=mlops-watchdog 를 1분마다 실행

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mlops-watchdog.timer

# --- 확인 ---
systemctl is-active --quiet mlops-watchdog.timer || die "mlops-watchdog.timer 가 실행 중이 아닙니다."
curl -sk -m 5 https://127.0.0.1:6443/livez >/dev/null || die "API 서버(127.0.0.1:6443)에 접속하지 못했습니다. 05-1 이 새 설정(127.0.0.1)으로 만든 클러스터인지 확인하세요."
login_flow_ok "127.0.0.1:8080" || die "127.0.0.1:8080 이 응답하지 않습니다 (journalctl -u kubeflow-port-forward)."
log "완료. 감시: systemctl list-timers mlops-watchdog.timer  로그: journalctl -u mlops-watchdog  시험: scripts/verify/08-boot-resilience.sh"
