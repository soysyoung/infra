#!/usr/bin/env bash
# 09-2. OpenSearch Dashboards 설치 (Helm 공식 차트, 브라우저에서 OpenSearch 를 보고 쿼리하는 웹 UI)
#
# 왜: REST API 만으로는 인덱스와 k-NN 쿼리를 살펴보기 불편해서. 설정과 근거는 docs/decisions/0017.
# 하는 일:
#   1) .env 의 OPENSEARCH_ADMIN_PASSWORD 로 Secret opensearch-dashboards-account 를 만든다 (차트가 username, password, cookie 를 읽는다)
#   2) 네임스페이스 opensearch 에 차트를 설치 (k8s/opensearch-dashboards-values.yaml)
#   3) systemd 서비스 opensearch-dashboards-port-forward 를 만들어 127.0.0.1:5601 port-forward 를 터미널 없이 계속 살려 둔다
#      (07-1 과 같은 방식. 여러 번 실행해도 안전하다)
# 접속: http://localhost:5601 (Service 는 ClusterIP 다. 127.0.0.1 에만 연다. 다른 tailnet 기기는 tailscale serve 로 따로 연다, ADR 0017)
#
# 선행: 09-1-opensearch.sh. 검증: scripts/verify/09-2-opensearch-dashboards.sh
#
# 참고 (공식 문서):
#   - https://docs.opensearch.org/latest/install-and-configure/install-dashboards/helm/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd helm "scripts/05-4-helm.sh 를 먼저 실행하세요."
NS=opensearch
RELEASE=opensearch-dashboards
SECRET=opensearch-dashboards-account

pw=$(sed -n 's/^OPENSEARCH_ADMIN_PASSWORD=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r')
[ -n "$pw" ] || die ".env 에 OPENSEARCH_ADMIN_PASSWORD 가 없습니다. scripts/09-1-opensearch.sh 를 먼저 실행하세요."
kubectl get ns "$NS" >/dev/null 2>&1 || die "네임스페이스 $NS 가 없습니다. scripts/09-1-opensearch.sh 를 먼저 실행하세요."

require_systemd
PORT=5601
UNIT=opensearch-dashboards-port-forward
# 서비스가 아닌 다른 프로세스(터미널에서 수동으로 띄운 port-forward 등)가 이미 잡고 있으면 서비스가 재시작을 반복한다.
holder=$(ss -ltnp "sport = :$PORT" 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2 || true)
svc=$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || echo 0)
[ -z "$holder" ] || [ "$holder" = "$svc" ] \
  || die "포트 $PORT 를 pid $holder 가 이미 쓰고 있습니다 (터미널에서 수동으로 띄운 port-forward 일 수 있음: ps -o pid,args -p $holder). 그 터미널에서 Ctrl+C 로 종료한 뒤 다시 실행하세요."

# 쿠키 암호화 키(32자 이상). 다시 실행해도 로그인이 풀리지 않도록 이미 있으면 그대로 쓴다.
cookie=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.cookie}' 2>/dev/null | base64 -d || true)
[ -n "$cookie" ] || cookie=$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32)
kubectl -n "$NS" create secret generic "$SECRET" \
  --from-literal=username=admin --from-literal=password="$pw" --from-literal=cookie="$cookie" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add opensearch https://opensearch-project.github.io/helm-charts/ --force-update >/dev/null
helm repo update opensearch >/dev/null
helm --kube-context "kind-$CLUSTER" upgrade --install "$RELEASE" opensearch/opensearch-dashboards \
  --version "$OPENSEARCH_DASHBOARDS_CHART_VERSION" -n "$NS" -f "$ROOT/k8s/opensearch-dashboards-values.yaml"

kubectl -n "$NS" rollout status deploy/opensearch-dashboards --timeout=600s

sudo tee "/etc/systemd/system/$UNIT.service" >/dev/null <<EOF
[Unit]
Description=OpenSearch Dashboards port-forward on localhost
After=docker.service

[Service]
User=$(id -un)
ExecStart=$(type -P kubectl) --context kind-$CLUSTER -n $NS port-forward --address 127.0.0.1 svc/opensearch-dashboards $PORT:5601
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now "$UNIT"

log "완료. 검증: scripts/verify/09-2-opensearch-dashboards.sh"
log "접속: http://localhost:$PORT (admin, .env 의 OPENSEARCH_ADMIN_PASSWORD). 로그: journalctl -u $UNIT"
log "파드가 Ready 여도 첫 1분쯤은 503 이 나올 수 있다 (공식 문서). 잠시 뒤 새로고침한다."
