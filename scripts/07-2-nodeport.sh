#!/usr/bin/env bash
# 07-2. Kubeflow 를 tailnet 에 상시 노출 (NodePort 방식: 게이트웨이 Service 를 NodePort 30080 으로)
#
# *** 사용하지 않는다 (docs/decisions/0011) ***
# Kubeflow 공식 문서가 NodePort 를 권하지 않고("서비스는 ClusterIP 만"), NodePort 로 localhost 가 아닌 주소에 HTTP 로 접속하면
# Secure 쿠키 때문에 웹앱이 동작하지 않는다. 시험과 기록을 위해 남겨 둔 스크립트다. 접속은 07-1 과 07-3 을 쓴다.
#
#
# 왜: port-forward 방식(07-1)은 kubectl 프로세스 하나가 API 서버를 거쳐 파드 하나로 터널을 연다.
#     NodePort 방식은 Docker 의 포트 매핑과 kube-proxy 가 처리해서 상시 도는 프로세스가 없고 파드가 바뀌어도 끊기지 않는다.
# 하는 일 (여러 번 실행해도 안전하다):
#   1) istio-ingressgateway Service 를 type NodePort, nodePort 30080 으로 바꾼다.
#   2) 게이트웨이 8080 으로 들어오는 트래픽을 허용하는 NetworkPolicy 를 더한다 (Kubeflow 기본 정책이 막는다, 아래 설명).
#   호스트 쪽 포트(<tailnet 주소>:30080 -> 노드 30080)는 kind 가 클러스터를 만들 때만 정할 수 있어서
#   k8s/kind-config.yaml 의 extraPortMappings 가 맡는다 (05-1). 매핑이 없는 클러스터면 안내하고 멈춘다.
# 주의: 06 을 다시 실행하면 Service 가 공식 구성(ClusterIP)으로 돌아가므로 이 스크립트를 다시 실행한다.
# 접속: http://<tailnet 주소>:30080  (tailscale ip -4)
# port-forward 방식(07-1)과 포트가 달라서 둘 다 켜 둘 수 있다. 비교는 docs/decisions/0009.
#
# 선행: 02, 05-1(포트 매핑이 있는 클러스터), 06   검증: scripts/verify/07-2-nodeport.sh
#
# 참고 (공식 문서):
#   - kind extraPortMappings: https://kind.sigs.k8s.io/docs/user/configuration/#extra-port-mappings
#   - NodePort: https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd docker "03-docker.sh 를 먼저 하세요."
require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."
require_cmd kubectl "05-1-kind-cluster.sh 를 먼저 하세요."
kubectl -n istio-system get svc istio-ingressgateway >/dev/null || die "06-kubeflow.sh 를 먼저 하세요."

PORT=30080
docker port "$CLUSTER-control-plane" "$PORT/tcp" >/dev/null 2>&1 \
  || die "클러스터에 호스트 포트 매핑($PORT)이 없습니다. kind 는 만든 뒤에 포트를 열 수 없으니 클러스터를 지우고 05-1 부터 다시 하세요 (scripts/README.md '클러스터만 다시 만들기')."

# 병합 키는 port+protocol 이라 protocol 을 빼면 nodePort 가 반영되지 않는다 (kustomize 빌드와 kubectl patch --local 로 확인).
kubectl -n istio-system patch svc istio-ingressgateway \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http2","port":80,"protocol":"TCP","nodePort":30080}]}}'

# Kubeflow 의 NetworkPolicy 는 istio-system 안에서 게이트웨이(8080)로 들어오는 트래픽을 같은 네임스페이스와
# knative-serving 에서만 허용한다. NodePort 로 들어온 트래픽은 노드에서 오므로 다른 노드의 게이트웨이 파드로 가다가
# 막혀 타임아웃이 난다 (노드 안에서 파드 IP 로 직접 가도 같은 노드만 되고 다른 노드는 막힘, 정책 없는 CoreDNS 는 노드 간 통신 정상).
# port-forward 는 kubelet 이 파드 안으로 직접 연결해서 이 정책을 거치지 않는다. 정책은 합집합으로 적용되므로 허용 규칙을 더한다.
# shortcut: 출발지를 가리지 않고 8080 을 모두에게 연다 (인증은 앞단의 oauth2-proxy 가 한다). 좁히려면 from.ipBlock 에 kind 도커 네트워크 대역을 쓴다.
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-gateway-nodeport
  namespace: istio-system
spec:
  podSelector:
    matchLabels:
      app: istio-ingressgateway
  policyTypes: [Ingress]
  ingress:
  - ports:
    - {port: 8080, protocol: TCP}
EOF

log "완료. http://$(tailscale ip -4):$PORT  검증: scripts/verify/07-2-nodeport.sh"
