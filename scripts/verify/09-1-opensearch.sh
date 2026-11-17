#!/usr/bin/env bash
# 09-1 검증: 파드 Ready -> 클러스터 상태 -> k-NN 플러그인 -> 384차원 벡터 색인과 검색 (시험 인덱스는 지운다)
# curl 은 파드 안에서 실행한다 (파드의 OPENSEARCH_INITIAL_ADMIN_PASSWORD 를 쓰므로 비밀번호가 명령줄에 나오지 않는다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=opensearch
POD=opensearch-cluster-master-0
kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s

# 보안 플러그인 초기화가 끝날 때까지 몇 번 다시 시도한다 ('OpenSearch Security not initialized').
os() { kubectl -n "$NS" exec "$POD" -- sh -c 'curl -sk -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -H "Content-Type: application/json" "$@"' sh "$@"; }
for _ in $(seq 30); do
  health=$(os "https://localhost:9200/_cluster/health" | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p')
  [ -n "$health" ] && break
  sleep 5
done
log "클러스터 상태: ${health:-응답 없음}"
case "${health:-}" in green|yellow) ;; *) die "클러스터가 응답하지 않거나 red 입니다 (비밀번호 거부 여부는 파드 로그 확인).";; esac

os "https://localhost:9200/_cat/plugins?h=component" | grep -qx "opensearch-knn" || die "k-NN 플러그인이 없습니다."
log "k-NN 플러그인: 있음"

idx=verify-knn
os -XDELETE "https://localhost:9200/$idx" >/dev/null
os -XPUT "https://localhost:9200/$idx" -d '{
  "settings": {"index": {"knn": true, "number_of_replicas": 0}},
  "mappings": {"properties": {"v": {"type": "knn_vector", "dimension": 384}}}}' | grep -q '"acknowledged":true' || die "k-NN 인덱스 생성 실패"
vec=$(python3 -c 'print(",".join(["0.1"]*384))')
os -XPOST "https://localhost:9200/$idx/_doc/1?refresh=true" -d "{\"v\":[$vec]}" | grep -q '"result":"created"' || die "벡터 색인 실패"
hits=$(os "https://localhost:9200/$idx/_search" -d "{\"size\":1,\"query\":{\"knn\":{\"v\":{\"vector\":[$vec],\"k\":1}}}}" | sed -n 's/.*"value":\([0-9]*\).*/\1/p' | head -1)
os -XDELETE "https://localhost:9200/$idx" >/dev/null
[ "${hits:-0}" -ge 1 ] || die "k-NN 검색 결과가 없습니다."

log "OK: 384차원 벡터 색인과 k-NN 검색 동작"
