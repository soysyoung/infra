#!/usr/bin/env bash
# 08 검증: 감시 서비스(mlops-watchdog)가 컨트롤 플레인 장애에서 스스로 복구하는가
#
# 주의: 클러스터를 일부러 멈춘다. 복구될 때까지 Kubeflow(localhost:8080)가 2~4분 끊긴다. 직접 실행한다.
# 사용: bash scripts/verify/08-boot-resilience.sh [detach|down]
#   detach (기본): 모든 노드를 멈추고 컨트롤 플레인을 kind 네트워크에서 뗀다. 2026-10-27 사고(Networks 가 비어 있음)와 같은 모양이다.
#   down         : 컨트롤 플레인만 멈춘다 (네트워크에는 붙은 채). 감시가 '2번 연속 실행 중이 아님' 으로 판단하는 경로.
# 한계: 사고의 원인(부팅 때 Docker 복원과 tailscale0 주소의 경합)을 재현하지 않고, 복구 경로만 시험한다.
#       통과해도 '경합이 막힌다' 는 뜻이 아니다 (그건 scripts/08-boot-resilience.sh 의 tailscale wait 가 맡는다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

CASE=${1:-detach}
[ "$CASE" = detach ] || [ "$CASE" = down ] || die "사용법: $0 [detach|down]"
CP=$CLUSTER-control-plane
NODES="$CLUSTER-worker $CLUSTER-worker2 $CLUSTER-worker3"
LIMIT=300   # 초. 감시는 1분마다 돌고 'down' 경로는 2번 연속 확인이 필요하다.

systemctl is-active --quiet mlops-watchdog.timer || die "mlops-watchdog.timer 가 실행 중이 아닙니다 (08-boot-resilience.sh 를 먼저 하세요)."
[ -r /etc/mlops/cp-ip ] || die "/etc/mlops/cp-ip 가 없습니다 (08-boot-resilience.sh 를 먼저 하세요)."
CP_IP=$(cat /etc/mlops/cp-ip)
kubectl wait --for=condition=Ready node --all --timeout=60s >/dev/null || die "시험 전에 노드 4개가 Ready 여야 합니다."
login_flow_ok "127.0.0.1:8080" || die "시험 전에 127.0.0.1:8080 이 응답해야 합니다."

START=$(date '+%Y-%m-%d %H:%M:%S')
if [ "$CASE" = detach ]; then
  log "[detach] 모든 노드를 멈추고 $CP 를 kind 네트워크에서 뗍니다"
  docker stop $NODES "$CP" >/dev/null
  docker network disconnect -f kind "$CP"
else
  log "[down] $CP 만 멈춥니다"
  docker stop "$CP" >/dev/null
fi

log "장애를 만들었습니다 ($START). 감시 서비스가 복구하기를 최대 ${LIMIT}초 기다립니다"
SECONDS=0
while [ "$SECONDS" -lt "$LIMIT" ]; do
  state=$(docker inspect -f '{{.State.Status}}' "$CP")
  ip=$(docker inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "$CP")
  running=$(docker ps -q --filter status=running --filter "name=$CLUSTER-" | wc -l)
  printf '  %3ss  %s  ip=%s  실행 중 노드=%s/4\n' "$SECONDS" "$state" "${ip:-없음}" "$running"
  [ "$state" = running ] && [ "$ip" = "$CP_IP" ] && [ "$running" = 4 ] && break
  sleep 10
done
RECOVERED=$SECONDS
[ "$state" = running ] && [ "$ip" = "$CP_IP" ] && [ "$running" = 4 ] \
  || { journalctl -u mlops-watchdog --since "$START" --no-pager | grep 'mlops-watchdog:' || true; die "${LIMIT}초 안에 복구되지 않았습니다 (docker ps -a, journalctl -u mlops-watchdog)."; }

log "노드 Ready 와 8080 응답을 기다립니다"
kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null || die "복구 뒤 노드가 Ready 가 되지 않았습니다."
for _ in $(seq 1 30); do login_flow_ok "127.0.0.1:8080" && ok=1 && break; sleep 5; done
[ "${ok:-}" = 1 ] || die "컨테이너는 복구됐지만 127.0.0.1:8080 이 응답하지 않습니다 (감시의 port-forward 재시작 경로 확인: journalctl -u mlops-watchdog)."
TOTAL=$SECONDS

echo; echo "--- 감시 서비스 기록 ($START 이후)"
journalctl -u mlops-watchdog --since "$START" --no-pager | grep 'mlops-watchdog:' || echo "(기록 없음: 감시가 아니라 다른 요인으로 복구됐을 수 있다)"
log "OK: [$CASE] 컨테이너 복구까지 ${RECOVERED}초, 8080 응답까지 총 ${TOTAL}초 (사람 조작 없음)"
