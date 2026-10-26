#!/usr/bin/env bash
# 07. Kubeflow 를 tailnet 에 상시 노출 (port-forward 방식: systemd 로 감싼 kubectl port-forward)
#
# 왜: kubectl port-forward 는 터미널을 닫으면 끊기고 127.0.0.1 에만 열린다. 다른 기기에서 tailnet 주소로 쓰려면
#     tailnet 주소에 바인딩한 port-forward 를 systemd 가 계속 살려 두어야 한다.
# 하는 일: /etc/systemd/system/kubeflow-port-forward.service 를 만들고 enable --now. 여러 번 실행해도 안전하다.
# 접속: http://<tailnet 주소>:8080  (tailscale ip -4)
# NodePort 방식(포트 30080)은 이 스크립트가 필요 없다. 클러스터를 만들 때 kind-config.yaml 이 연다. 비교는 docs/decisions/0009.
#
# 선행: 02, 05-1, 06   검증: scripts/verify/07-expose.sh
# 주의: 비밀번호(.env)를 바꾸기 전에는 tailnet 에도 열지 않는다.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_systemd
require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."
require_cmd kubectl "05-1-kind-cluster.sh 를 먼저 하세요."
kubectl -n istio-system get svc istio-ingressgateway >/dev/null || die "06-kubeflow.sh 를 먼저 하세요."

PORT=8080
TAILNET_IP=$(tailscale ip -4)
# 같은 주소에 이미 다른 프로세스(수동 port-forward 등)가 있으면 서비스가 재시작을 반복한다.
if ss -ltn "sport = :$PORT" | grep -q "$TAILNET_IP"; then
  systemctl is-active --quiet kubeflow-port-forward || die "$TAILNET_IP:$PORT 를 이미 쓰는 프로세스가 있습니다 (ss -ltnp | grep $PORT)."
fi

sudo tee /etc/systemd/system/kubeflow-port-forward.service >/dev/null <<EOF
[Unit]
Description=Kubeflow port-forward on tailnet
After=docker.service tailscaled.service
Wants=tailscaled.service

[Service]
User=$(id -un)
ExecStart=$(type -P kubectl) --context kind-$CLUSTER -n istio-system port-forward --address $TAILNET_IP svc/istio-ingressgateway $PORT:80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now kubeflow-port-forward
sudo systemctl restart kubeflow-port-forward   # tailnet 주소가 바뀐 뒤 다시 실행했을 때 새 주소를 반영한다

log "완료. http://$TAILNET_IP:$PORT  검증: scripts/verify/07-expose.sh"
