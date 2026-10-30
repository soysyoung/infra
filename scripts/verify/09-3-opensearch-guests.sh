#!/usr/bin/env bash
# 09-3 검증: 게스트 두 계정이 허용된 일은 되고 허용되지 않은 일은 거부(403)되는지.
# 계정 비밀번호는 curl 설정을 표준입력(-K -)으로 넘겨서 명령줄에 나오지 않게 한다. 시험 인덱스는 끝에 지운다.
# 시험하지 않는 것: guest-ro 의 Dashboards 로그인 (브라우저에서 확인한다).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=opensearch
POD=opensearch-cluster-master-0
ENV_FILE="$ROOT/.env"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" 2>/dev/null | tr -d '\r' | tail -1; }
rw_user=$(env_get OPENSEARCH_GUEST_RW_USER); rw_pw=$(env_get OPENSEARCH_GUEST_RW_PASSWORD)
ro_user=$(env_get OPENSEARCH_GUEST_RO_USER); ro_pw=$(env_get OPENSEARCH_GUEST_RO_PASSWORD)
[ -n "$rw_user" ] && [ -n "$rw_pw" ] && [ -n "$ro_user" ] && [ -n "$ro_pw" ] \
  || die ".env 에 게스트 계정이 없습니다. scripts/09-3-opensearch-guests.sh 를 먼저 실행하세요."
kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s

# adm: admin 으로 호출 (파드의 비밀번호 환경변수 사용), 본문을 낸다
adm() { kubectl -n "$NS" exec "$POD" -c opensearch -- sh -c 'curl -sk -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -H "Content-Type: application/json" "$@"' sh "$@"; }
# as USER PASS METHOD PATH [BODY]: 그 계정으로 호출해 HTTP 코드만 낸다
as() {
  printf 'user = "%s:%s"\n' "$1" "$2" | kubectl -n "$NS" exec -i "$POD" -c opensearch -- \
    curl -sk -o /dev/null -w '%{http_code}' -K - -X "$3" -H 'Content-Type: application/json' ${5:+--data-binary "$5"} "https://localhost:9200$4"
}

# 시험 인덱스 이름은 역할의 인덱스 패턴에서 얻는다 (09-3 의 INDEX_PATTERN 이 단일 출처)
pat=$(adm https://localhost:9200/_plugins/_security/api/roles/guest_rw | python3 -c 'import sys,json; print(json.load(sys.stdin)["guest_rw"]["index_permissions"][0]["index_patterns"][0])') \
  || die "guest_rw 역할을 읽지 못했습니다."
prefix=${pat%\*}
idx="${prefix}verify-guest"
outside="verify-outside-guest"
log "인덱스 패턴 $pat, 시험 인덱스 $idx, 범위 밖 인덱스 $outside"
cleanup() { adm -XDELETE "https://localhost:9200/$idx" >/dev/null 2>&1 || true; adm -XDELETE "https://localhost:9200/$outside" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

fail=0
expect() { if [ "$3" = "$2" ]; then log "OK    $1 ($3)"; else fail=1; echo "실패  $1: 기대 $2, 실제 $3" >&2; fi; }
vec=$(python3 -c 'print(",".join(["0.1"]*384))')
mapping='{"settings":{"index":{"knn":true,"number_of_replicas":0}},"mappings":{"properties":{"v":{"type":"knn_vector","dimension":384}}}}'
bulk=$'{"index":{"_index":"'"$idx"$'","_id":"2"}}\n{"v":['"$vec"$']}\n'
knn="{\"size\":1,\"query\":{\"knn\":{\"v\":{\"vector\":[$vec],\"k\":1}}}}"

expect "guest-rw 가 인덱스를 만든다"        200 "$(as "$rw_user" "$rw_pw" PUT "/$idx" "$mapping")"
expect "guest-rw 가 문서를 색인한다"        201 "$(as "$rw_user" "$rw_pw" PUT "/$idx/_doc/1?refresh=true" "{\"v\":[$vec]}")"
expect "guest-rw 가 bulk 로 색인한다"       200 "$(as "$rw_user" "$rw_pw" POST "/_bulk?refresh=true" "$bulk")"
expect "guest-rw 가 k-NN 검색한다"          200 "$(as "$rw_user" "$rw_pw" POST "/$idx/_search" "$knn")"
expect "guest-rw 가 범위 밖 인덱스를 만들지 못한다" 403 "$(as "$rw_user" "$rw_pw" PUT "/$outside" "$mapping")"
expect "guest-rw 가 시스템 인덱스를 읽지 못한다"   403 "$(as "$rw_user" "$rw_pw" GET "/.kibana/_search")"
expect "guest-ro 가 k-NN 검색한다"          200 "$(as "$ro_user" "$ro_pw" POST "/$idx/_search" "$knn")"
expect "guest-ro 가 문서를 쓰지 못한다"     403 "$(as "$ro_user" "$ro_pw" PUT "/$idx/_doc/9" "{\"v\":[$vec]}")"
expect "guest-ro 가 인덱스를 지우지 못한다" 403 "$(as "$ro_user" "$ro_pw" DELETE "/$idx")"
expect "guest-ro 가 범위 밖 인덱스를 읽지 못한다" 403 "$(as "$ro_user" "$ro_pw" POST "/$outside/_search" "$knn")"
expect "guest-ro 가 클러스터 설정을 읽지 못한다"   403 "$(as "$ro_user" "$ro_pw" GET "/_cluster/settings")"
expect "guest-rw 가 인덱스를 지운다"        200 "$(as "$rw_user" "$rw_pw" DELETE "/$idx")"

[ "$fail" = 0 ] || die "실패한 항목이 있습니다. 위 '실패' 줄을 보세요."
log "OK: 게스트 권한 분리가 기대대로 동작 (Dashboards 로그인은 브라우저로 확인)"
