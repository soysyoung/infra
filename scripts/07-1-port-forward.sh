#!/usr/bin/env bash
# 07-1. Kubeflow 접속의 기본 경로: systemd 로 감싼 kubectl port-forward (127.0.0.1:8080)
#
# 왜: Kubeflow 공식 기본 접속이 port-forward 다 (kubeflow/community-distribution). 게이트웨이 Service 는 ClusterIP 그대로 둔다.
#     터미널을 닫으면 끊기는 것을 systemd 가 계속 살려 둔다.
#     127.0.0.1 에만 연다. localhost 는 HTTP 여도 브라우저가 Secure 쿠키를 허용한다 (이 PC 의 Windows 브라우저도
#     mirrored 네트워킹으로 http://localhost:8080 이 된다). tailnet 의 다른 기기는 07-3 의 HTTPS 로 접속한다.
#     tailnet 주소에 HTTP 로 열지 않는 이유: Kubeflow 웹앱(Jupyter 등)이 Secure 쿠키를 써서 localhost 가 아닌 주소에
#     HTTP 로 접속하면 동작하지 않는다 (docs/decisions/0011).
# 하는 일: /etc/systemd/system/kubeflow-port-forward.service 를 만들고 enable --now. 여러 번 실행해도 안전하다.
# 접속: http://localhost:8080
#
# 선행: 05-1, 06   검증: scripts/verify/07-1-port-forward.sh
# 주의: 수동으로 띄운 kubectl port-forward 가 127.0.0.1:8080 을 잡고 있으면 먼저 종료한다 (아래에서 확인한다).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_systemd
require_cmd kubectl "05-1-kind-cluster.sh 를 먼저 하세요."
kubectl -n istio-system get svc istio-ingressgateway >/dev/null || die "06-kubeflow.sh 를 먼저 하세요."

PORT=8080
# 서비스가 아닌 다른 프로세스(수동 port-forward 등)가 이미 잡고 있으면 서비스가 재시작을 반복한다.
holder=$(ss -ltnp "sport = :$PORT" 2>/dev/null | grep "127.0.0.1:$PORT" | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2 || true)
svc=$(systemctl show -p MainPID --value kubeflow-port-forward 2>/dev/null || echo 0)
[ -z "$holder" ] || [ "$holder" = "$svc" ] \
  || die "127.0.0.1:$PORT 를 pid $holder 가 이미 쓰고 있습니다 (수동으로 띄운 port-forward 일 수 있음: ps -o pid,args -p $holder). 종료한 뒤 다시 실행하세요."

sudo tee /etc/systemd/system/kubeflow-port-forward.service >/dev/null <<EOF
[Unit]
Description=Kubeflow port-forward on localhost
After=docker.service

[Service]
User=$(id -un)
ExecStart=$(type -P kubectl) --context kind-$CLUSTER -n istio-system port-forward --address 127.0.0.1 svc/istio-ingressgateway $PORT:80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now kubeflow-port-forward
sudo systemctl restart kubeflow-port-forward   # 이전 버전(tailnet 주소 바인딩)의 서비스를 새 주소로 바꾼다

log "완료. http://localhost:$PORT  다른 기기는 07-3-tailscale-serve.sh  검증: scripts/verify/07-1-port-forward.sh"
