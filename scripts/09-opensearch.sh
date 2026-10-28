#!/usr/bin/env bash
# 09. OpenSearch 단일 노드 설치 (Helm 공식 차트, k-NN 벡터 검색용)
#
# 왜: 추천 서비스의 벡터 검색(약 10.5만 x 384차원)을 클러스터 안에서 제공한다. 설정과 근거는 docs/decisions/0014.
# 하는 일:
#   1) 관리자 비밀번호가 .env 에 없으면 만들어서 추가 (OpenSearch 2.12+ 는 초기 비밀번호가 필수)
#   2) 네임스페이스 opensearch 에 Secret 과 차트를 설치 (k8s/opensearch-values.yaml)
# 주의: 릴리스를 지워도 PVC 는 남고, 다시 설치하면 처음 비밀번호가 그대로 쓰인다 (teardown/09 가 PVC 도 지운다).
#
# 선행: 06-kubeflow.sh 까지 (StorageClass 와 노드), 05-4-helm.sh. 검증: scripts/verify/09-opensearch.sh
#
# 참고 (공식 문서):
#   - https://docs.opensearch.org/latest/install-and-configure/install-opensearch/helm/
#   - 비밀번호 요구: https://docs.opensearch.org/latest/security/configuration/demo-configuration/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd helm "scripts/05-4-helm.sh 를 먼저 실행하세요."
NS=opensearch
RELEASE=opensearch


# 비밀번호: 8~100자, 대소문자, 숫자, 특수문자를 모두 포함하고 zxcvbn 'strong' 이상이어야 한다 (공식 문서).
# 무작위 20자에 네 종류를 보장하는 접미사를 붙인다. 이미 .env 에 있으면 그대로 쓴다 (PVC 가 처음 값을 기억한다).
ENV_FILE="$ROOT/.env"
pw=$(sed -n 's/^OPENSEARCH_ADMIN_PASSWORD=//p' "$ENV_FILE" 2>/dev/null | tr -d '\r')
if [ -z "$pw" ]; then
  pw="$(openssl rand -base64 30 | tr -d '/+=\n' | cut -c1-20)aZ9#"
  { [ ! -s "$ENV_FILE" ] || [ -z "$(tail -c1 "$ENV_FILE")" ] || echo; echo "OPENSEARCH_ADMIN_PASSWORD=$pw"; } >> "$ENV_FILE"
  log ".env 에 OPENSEARCH_ADMIN_PASSWORD 를 만들었습니다."
fi

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
kubectl -n "$NS" create secret generic opensearch-admin --from-literal=password="$pw" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add opensearch https://opensearch-project.github.io/helm-charts/ --force-update >/dev/null
helm repo update opensearch >/dev/null
# extraEnvs 는 한 번만 정의해야 한다 (두 번째 키가 첫 번째를 조용히 덮어쓴다, 공식 문서 Common issues).
helm --kube-context "kind-$CLUSTER" upgrade --install "$RELEASE" opensearch/opensearch \
  --version "$OPENSEARCH_CHART_VERSION" -n "$NS" -f "$ROOT/k8s/opensearch-values.yaml" \
  --set 'extraEnvs[0].name=OPENSEARCH_INITIAL_ADMIN_PASSWORD' \
  --set 'extraEnvs[0].valueFrom.secretKeyRef.name=opensearch-admin' \
  --set 'extraEnvs[0].valueFrom.secretKeyRef.key=password'

kubectl -n "$NS" rollout status sts/opensearch-cluster-master --timeout=600s

log "완료. 검증: scripts/verify/09-opensearch.sh  (접속: kubectl -n $NS port-forward svc/opensearch-cluster-master 9200:9200)"
