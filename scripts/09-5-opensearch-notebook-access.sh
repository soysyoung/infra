#!/usr/bin/env bash
# 09-5. Notebook 에 OpenSearch guest-rw 접속 정보를 환경변수로 넣는다 (Secret + PodDefault, 프로필 네임스페이스마다)
#
# 왜: Notebook 에 admin 비밀번호를 두지 않으려고. 설계와 근거는 docs/decisions/0020.
# 하는 일 (여러 번 실행해도 안전):
#   대상 네임스페이스마다 (06-4 와 같은 목록: 기본 사용자, .env 에 EXTRA_USER_EMAIL 이 있으면 두 번째 사용자)
#   1) Secret opensearch-guest 를 .env 의 guest-rw 이름과 비밀번호로 만들거나 갱신한다
#   2) PodDefault opensearch-guest (k8s/opensearch-guest-poddefault.yaml) 를 적용한다
# 쓰는 법: Notebook 을 만들 때 Configurations 에서 'OpenSearch guest-rw 접속 정보' 를 고른다. 파드에 OPENSEARCH_URL,
#   OPENSEARCH_USER, OPENSEARCH_PASSWORD 가 들어간다. 이미 떠 있는 Notebook 은 재시작해야 반영된다.
# 비밀번호를 바꾸려면 .env 를 고치고 09-3 -> 09-5 를 다시 실행한다 (실행 중인 Notebook 은 재시작).
#
# 선행: 09-3 (guest-rw 계정), 06 (프로필 네임스페이스). 두 번째 사용자는 06-2. 검증: scripts/verify/09-5-opensearch-notebook-access.sh
# 되돌리기: scripts/teardown/09-5-opensearch-notebook-access.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/quotas.sh"   # quota_targets: 대상 프로필 목록만 쓴다

env_get() { sed -n "s/^$1=//p" "$ROOT/.env" 2>/dev/null | tr -d '\r' | tail -1; }
user=$(env_get OPENSEARCH_GUEST_RW_USER); pw=$(env_get OPENSEARCH_GUEST_RW_PASSWORD)
[ -n "$user" ] && [ -n "$pw" ] || die ".env 에 guest-rw 계정이 없습니다. scripts/09-3-opensearch-guests.sh 를 먼저 실행하세요."
kubectl -n opensearch get svc opensearch-cluster-master >/dev/null 2>&1 || die "OpenSearch 서비스가 없습니다. scripts/09-1-opensearch.sh 를 먼저 실행하세요."

n=0
while read -r ns _; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    log "네임스페이스 $ns 가 아직 없어 건너뜁니다 (두 번째 사용자는 06-2-extra-user.sh 를 먼저 실행)."
    continue
  fi
  kubectl -n "$ns" create secret generic opensearch-guest \
    --from-literal=username="$user" --from-literal=password="$pw" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" apply -f "$ROOT/k8s/opensearch-guest-poddefault.yaml"
  n=$((n + 1))
done < <(quota_targets)
[ "$n" -gt 0 ] || die "대상 네임스페이스가 하나도 없습니다. 06-kubeflow.sh 가 끝났는지 확인하세요."

log "완료 ($n 개 네임스페이스). 검증: scripts/verify/09-5-opensearch-notebook-access.sh"
log "Notebook 을 만들 때 Configurations 에서 'OpenSearch guest-rw 접속 정보' 를 고르세요. 떠 있는 Notebook 은 재시작해야 반영됩니다."
