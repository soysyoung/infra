#!/usr/bin/env bash
# 08. 재부팅·네트워크 전환에도 http://localhost:8080 이 돌아오게 하는 세 겹의 장치 (docs/decisions/0010 '사고 기록')
#
# 왜: 2026-10-27 에 컨트롤 플레인 컨테이너가 kind 네트워크에서 떨어져 8080 이 막혔다. 컨트롤 플레인만 tailnet 주소로 포트를
#     게시하는데, 부팅 때 Docker 가 그 컨테이너를 복원하는 순간 tailscale0 의 주소가 아직 없었던 것으로 보인다 (정황).
#     또 port-forward 가 API 서버를 tailnet 주소로 불러서 이더넷/와이파이가 바뀌어 tailscaled 가 흔들리면 같이 죽었다.
# 하는 일:
#   1) docker.service 시작 전에 'tailscale wait' (최대 60초). 시간이 지나면 그냥 시작한다 (Tailscale 이 로그아웃이어도 Docker 는 떠야 한다).
#   2) port-forward 서비스가 tailnet 주소 대신 컨트롤 플레인 컨테이너 IP 로 API 서버를 부르게 한다 (전용 kubeconfig + drop-in).
#      API 서버 인증서의 SAN 에 그 IP 가 들어 있다. tailscale0 와 물리 NIC 에 의존하지 않는다.
#   3) 1분마다 도는 감시 서비스: 컨트롤 플레인이 kind 네트워크에서 빠졌으면 같은 IP 로 다시 붙이고, 8080 이 2번 연속 응답하지
#      않으면 port-forward 서비스를 재시작한다.
# 여러 번 실행해도 안전하다. sudo 가 필요하다.
#
# 선행: 05-1, 06, 07-1 (컨트롤 플레인이 kind 네트워크에 붙어 실행 중이어야 한다)   검증: 끝에서 스스로 확인한다
# shortcut: 컨트롤 플레인 IP 는 지금 값을 /etc/mlops/cp-ip 에 고정해 쓴다. 클러스터를 다시 만들면 이 스크립트를 다시 실행한다.
# shortcut: 'docker network connect --ip' 가 재시작 뒤에도 IP 를 유지하는지는 시험하지 않았다. 유지되지 않아도 감시 서비스가 되붙인다.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_systemd
require_cmd docker
require_cmd tailscale
require_cmd kubectl "05-1-kind-cluster.sh 를 먼저 하세요."
systemctl cat kubeflow-port-forward >/dev/null 2>&1 || die "07-1-port-forward.sh 를 먼저 하세요."

CP=$CLUSTER-control-plane
CP_IP=$(docker inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "$CP" 2>/dev/null || true)
[ -n "$CP_IP" ] || die "$CP 가 kind 네트워크에 붙어 있지 않습니다. 먼저 컨트롤 플레인을 복구하세요 (docs/decisions/0010 '복구')."
log "컨트롤 플레인 IP: $CP_IP"

# --- 1) docker.service: tailscale0 에 주소가 생길 때까지 기다린다 ---
# '-' 접두사: 시간 초과(비정상 종료)여도 Docker 는 시작한다.
sudo install -d /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/10-tailscale-wait.conf >/dev/null <<EOF
[Unit]
Wants=tailscaled.service
After=tailscaled.service

[Service]
ExecStartPre=-$(type -P tailscale) wait --timeout=60s
EOF
# 플래그 값이 틀려도 '-' 때문에 Docker 는 그냥 뜨므로, 같은 명령이 지금 통과하는지 직접 돌려 본다.
tailscale wait --timeout=60s || die "tailscale wait --timeout=60s 가 실패했습니다 (Tailscale 이 준비되지 않았거나 플래그가 틀림)."

# --- 2) port-forward 가 컨테이너 IP 로 API 서버를 부르게 한다 ---
sudo install -d -m 755 /etc/mlops
echo "$CP_IP" | sudo tee /etc/mlops/cp-ip >/dev/null
KC="$HOME/.kube/mlops-local.config"
kubectl config view --minify --flatten >"$KC"
chmod 600 "$KC"
KUBECONFIG="$KC" command kubectl config set-cluster "kind-$CLUSTER" --server="https://$CP_IP:6443" >/dev/null

sudo install -d /etc/systemd/system/kubeflow-port-forward.service.d
sudo tee /etc/systemd/system/kubeflow-port-forward.service.d/10-local-api.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=$(type -P kubectl) --kubeconfig $KC --context kind-$CLUSTER -n istio-system port-forward --address 127.0.0.1 svc/istio-ingressgateway 8080:80
EOF

# --- 3) 감시 서비스 ---
sudo tee /usr/local/sbin/mlops-watchdog >/dev/null <<'EOF'
#!/usr/bin/env bash
# 1분마다 mlops-watchdog.timer 가 실행한다. 설치: scripts/08-boot-resilience.sh
set -u
CP=mlops-control-plane
NODES="mlops-worker mlops-worker2 mlops-worker3"
CP_IP=$(cat /etc/mlops/cp-ip)
FAILS=/run/mlops-watchdog.fails
say() { echo "mlops-watchdog: $*"; }

systemctl is-active --quiet docker || { say "docker 가 실행 중이 아님, 건너뜀"; exit 0; }
docker inspect "$CP" >/dev/null 2>&1 || { say "$CP 컨테이너가 없음, 건너뜀"; exit 0; }

# (a) 컨트롤 플레인이 kind 네트워크에서 빠졌으면 같은 IP 로 다시 붙인다.
attached=$(docker inspect -f '{{if index .NetworkSettings.Networks "kind"}}yes{{end}}' "$CP")
# 붙어 있어도 실행 중이 아니면 센다. 고정 IP 를 다른 컨테이너가 먼저 가져가면 컨트롤 플레인은 시작에 실패한다 (Docker 문서).
# 2번 연속(약 2분)이면 복구한다. 일부러 멈춰 둔 클러스터도 이 때문에 다시 시작되니, 멈추려면 mlops-watchdog.timer 도 멈춘다.
DOWN=/run/mlops-watchdog.down
if [ -n "$attached" ] && [ "$(docker inspect -f '{{.State.Status}}' "$CP")" != running ]; then
  n=$(( $(cat "$DOWN" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$DOWN"
  [ "$n" -ge 2 ] && attached="" || { say "$CP 가 실행 중이 아님 ($n/2), 다음 실행에서 다시 확인"; exit 0; }
fi
if [ -z "$attached" ]; then
  rm -f "$DOWN"
  # 포트를 tailnet 주소로 게시하므로 tailscale0 에 주소가 없으면 시작이 또 실패한다. 다음 실행에서 다시 본다.
  ip -4 addr show dev tailscale0 2>/dev/null | grep -q 'inet 100\.' || { say "컨트롤 플레인이 네트워크에서 빠졌지만 tailscale0 에 주소가 아직 없음, 다음 실행에서 재시도"; exit 0; }
  say "컨트롤 플레인이 kind 네트워크에서 빠짐 -> $CP_IP 로 다시 붙임"
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
api=$(curl -sk -m 5 -o /dev/null -w '%{http_code}' "https://$CP_IP:6443/livez" || true)
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
sudo systemctl restart kubeflow-port-forward   # 전용 kubeconfig 로 바꾼다

# --- 확인 ---
log "docker 시작 전 대기: $(systemctl show docker -p ExecStartPre --value | grep -o 'tailscale wait[^;]*' | head -1) (다음 부팅부터 적용. 결과: journalctl -b -u docker | grep -i tailscale)"
KUBECONFIG="$KC" command kubectl --context "kind-$CLUSTER" get nodes >/dev/null || die "전용 kubeconfig($KC)로 API 서버에 접속하지 못했습니다."
log "전용 kubeconfig 로 API 서버(https://$CP_IP:6443) 접속 확인"
for _ in $(seq 1 20); do login_flow_ok "127.0.0.1:8080" && ok=1 && break; sleep 3; done
[ "${ok:-}" = 1 ] || die "port-forward 재시작 후 127.0.0.1:8080 이 응답하지 않습니다 (journalctl -u kubeflow-port-forward)."
log "완료. 감시: systemctl list-timers mlops-watchdog.timer  로그: journalctl -u mlops-watchdog"
