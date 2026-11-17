#!/usr/bin/env bash
# 10-1. PostgreSQL 단일 인스턴스 설치 (CloudNativePG 연산자 Helm 차트 + Cluster 매니페스트)
#
# 왜: 클러스터 안에서 쓰는 관계형 DB(원본 데이터). 검색용 OpenSearch(09)와 역할이 다르다. 근거는 docs/decisions/0021.
# 하는 일:
#   1) 앱 계정 비밀번호가 .env 에 없으면 만들어서 추가 (공식 기본값인 무작위 생성과 다르다: 재설치해도 같은 값을 쓰려고, ADR 0021)
#   2) 네임스페이스 cnpg-system 에 연산자 설치 (helm, 차트 버전 고정)
#   3) 네임스페이스 postgres 에 basic-auth Secret postgres-app-auth 와 Cluster 1개 적용 (k8s/postgres-cluster.yaml), Ready 까지 대기
# 접속 정보: .env 의 POSTGRES_APP_USER, POSTGRES_APP_PASSWORD (DB app). 서비스 postgres-rw.postgres.svc:5432
# 주의: 비밀번호는 데이터베이스를 처음 만들 때만 쓰인다. 이미 초기화된 Cluster 에서는 .env 만 고쳐서는 바뀌지 않는다.
#
# 선행: 06-kubeflow.sh 까지 (StorageClass 와 노드), 05-4-helm.sh. 검증: scripts/verify/10-1-postgres.sh
#
# 참고 (공식 문서):
#   - https://github.com/cloudnative-pg/charts/blob/main/charts/cloudnative-pg/README.md
#   - https://cloudnative-pg.io/docs/1.30/installation_upgrade/
#   - https://cloudnative-pg.io/docs/1.30/bootstrap/ (initdb.secret: kubernetes.io/basic-auth)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd helm "scripts/05-4-helm.sh 를 먼저 실행하세요."
NS=postgres

# 무작위 32자 (영숫자만: 접속 URI 에 넣어도 인코딩이 필요 없다). 이미 .env 에 있으면 그대로 쓴다.
ENV_FILE="$ROOT/.env"
pw=$(sed -n 's/^POSTGRES_APP_PASSWORD=//p' "$ENV_FILE" 2>/dev/null | tr -d '\r')
if [ -z "$pw" ]; then
  pw="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32)"
  { [ ! -s "$ENV_FILE" ] || [ -z "$(tail -c1 "$ENV_FILE")" ] || echo; echo "POSTGRES_APP_PASSWORD=$pw"; } >> "$ENV_FILE"
  log ".env 에 POSTGRES_APP_PASSWORD 를 만들었습니다."
fi
# 계정 이름은 Cluster 의 bootstrap.initdb.owner(app)와 같아야 한다. 로그인할 때 보려고 적을 뿐 스크립트는 읽지 않는다.
grep -q '^POSTGRES_APP_USER=' "$ENV_FILE" || { [ -z "$(tail -c1 "$ENV_FILE")" ] || echo >> "$ENV_FILE"; echo "POSTGRES_APP_USER=app" >> "$ENV_FILE"; }

helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update >/dev/null
helm repo update cnpg >/dev/null
helm --kube-context "kind-$CLUSTER" upgrade --install cnpg cnpg/cloudnative-pg \
  --version "$CNPG_CHART_VERSION" -n cnpg-system --create-namespace
kubectl -n cnpg-system rollout status deploy/cnpg-cloudnative-pg --timeout=300s

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
kubectl -n "$NS" create secret generic postgres-app-auth --type=kubernetes.io/basic-auth \
  --from-literal=username=app --from-literal=password="$pw" --dry-run=client -o yaml | kubectl apply -f -
# 웹훅이 막 떠서 첫 적용이 거부될 수 있어 몇 번 다시 시도한다.
for i in $(seq 6); do
  sed "s|__POSTGRES_IMAGE__|$POSTGRES_IMAGE|" "$ROOT/k8s/postgres-cluster.yaml" | kubectl apply -f - && break
  [ "$i" = 6 ] && die "Cluster 적용 실패"
  sleep 10
done
kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=600s

log "완료. 검증: scripts/verify/10-1-postgres.sh (접속: kubectl -n $NS port-forward svc/postgres-rw 5432:5432)"
