#!/usr/bin/env bash
# 08 검증: 재부팅 후 사람이 아무것도 하지 않아도 서버로 돌아왔는가
# 재부팅하고 로그인하지 않은 채 기다린 뒤(다른 기기에서 tailnet 으로 SSH 하거나 WSL 을 열어) 실행한다.
# 확인: 서비스(docker, tailscaled, kubeflow-port-forward) -> 노드 컨테이너 재시작 정책 -> 노드 Ready -> tailnet 접속
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

for s in docker tailscaled kubeflow-port-forward; do
  systemctl is-active --quiet "$s" || die "$s 서비스가 실행 중이 아닙니다 (systemctl status $s)."
  log "$s: active"
done
log "WSL 가동 시간: $(uptime -p)"

for n in $(kind get nodes --name "$CLUSTER"); do
  policy=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$n")
  [ "$policy" = unless-stopped ] || die "$n 의 재시작 정책이 $policy 입니다 (05-1-kind-cluster.sh 를 다시 실행하면 고쳐집니다)."
done
log "노드 컨테이너 재시작 정책: unless-stopped"

kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed" {bad++; print} END{exit bad>0}' \
  || die "Running/Completed 가 아닌 파드가 있습니다 (재부팅 직후에는 몇 분 걸릴 수 있으니 잠시 뒤 다시 실행)."

bash "$(dirname "$0")/07-expose.sh"
log "OK: 재부팅 후 서비스, 노드, Kubeflow 접속이 모두 돌아옴"
