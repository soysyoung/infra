#!/usr/bin/env bash
# 09-3. OpenSearch 게스트 계정 2개 (역할 분리). Notebook 용은 쓰기·읽기, Dashboards 용은 읽기 전용
#
# 왜: Notebook 이나 외부 공유에 admin 비밀번호를 넘기지 않으려고. 설계와 근거는 docs/decisions/0018.
# 하는 일 (보안 REST API 를 OpenSearch 파드 안에서 admin 으로 호출한다):
#   1) .env 에 게스트 계정 이름과 비밀번호가 없으면 만들어서 추가 (이름 guest-rw, guest-ro, 비밀번호는 무작위)
#   2) 사용자 2개, 역할 2개(guest_rw, guest_ro), 역할 매핑 2개를 만든다 (PUT 이라 다시 실행하면 .env 값으로 맞춰진다)
#      - guest_rw: INDEX_PATTERN 인덱스에만 모든 인덱스 권한(indices_all) + bulk (cluster_composite_ops)
#      - guest_ro: INDEX_PATTERN 인덱스에만 읽기(read) + cluster_composite_ops_ro, Dashboards 로그인용 kibana_user 역할
# 직접 정하려면: 이 스크립트를 실행하기 전에 .env 에 OPENSEARCH_GUEST_RW_USER 등을 적는다 (비밀번호에 " 와 \ 는 쓰지 않는다).
# 주의: 계정은 OpenSearch 의 PVC 안에 있다. teardown/09-1 이나 비밀번호 재설정(securityadmin) 뒤에는 이 스크립트를 다시 실행한다.
#       .env 의 이름을 바꿔 다시 실행하면 옛 이름의 사용자는 그대로 남는다 (지우지 않는다).
#
# 선행: 09-1-opensearch.sh. 검증: scripts/verify/09-3-opensearch-guests.sh
#
# 참고 (공식 문서): https://docs.opensearch.org/latest/security/api/users/create-user/
#   https://docs.opensearch.org/latest/security/api/roles/create-role/
#   https://docs.opensearch.org/latest/security/api/role-mappings/create-role-mapping/
#   https://docs.opensearch.org/latest/security/access-control/default-action-groups/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=opensearch
POD=opensearch-cluster-master-0
INDEX_PATTERN="temp-*"   # 게스트가 접근할 인덱스. 워크로드의 인덱스 이름과 맞춘다. 바꾸고 다시 실행하면 역할이 갱신된다.
ENV_FILE="$ROOT/.env"

env_get() { sed -n "s/^$1=//p" "$ENV_FILE" 2>/dev/null | tr -d '\r' | tail -1; }
env_add() { [ ! -s "$ENV_FILE" ] || [ -z "$(tail -c1 "$ENV_FILE")" ] || echo >> "$ENV_FILE"; echo "$1=$2" >> "$ENV_FILE"; }
# 이미 값이 있으면 그대로 둔다. 비밀번호는 09-1 과 같은 방식(무작위 20자 + 네 종류를 보장하는 접미사)으로 만든다.
ensure() { [ -n "$(env_get "$1")" ] || { env_add "$1" "$2"; log ".env 에 $1 를 만들었습니다."; }; }
gen() { echo "$(openssl rand -base64 30 | tr -d '/+=\n' | cut -c1-20)aZ9#"; }

[ -n "$(env_get OPENSEARCH_ADMIN_PASSWORD)" ] || die ".env 에 OPENSEARCH_ADMIN_PASSWORD 가 없습니다. scripts/09-1-opensearch.sh 를 먼저 실행하세요."
ensure OPENSEARCH_GUEST_RW_USER guest-rw
ensure OPENSEARCH_GUEST_RW_PASSWORD "$(gen)"
ensure OPENSEARCH_GUEST_RO_USER guest-ro
ensure OPENSEARCH_GUEST_RO_PASSWORD "$(gen)"
rw_user=$(env_get OPENSEARCH_GUEST_RW_USER); rw_pw=$(env_get OPENSEARCH_GUEST_RW_PASSWORD)
ro_user=$(env_get OPENSEARCH_GUEST_RO_USER); ro_pw=$(env_get OPENSEARCH_GUEST_RO_PASSWORD)

# JSON 을 손으로 만들므로 이름과 비밀번호의 문자를 제한한다.
for u in "$rw_user" "$ro_user"; do
  [[ "$u" =~ ^[A-Za-z0-9_-]+$ ]] || die "계정 이름은 영문, 숫자, _, - 만 쓸 수 있습니다: $u"
done
[ "$rw_user" != "$ro_user" ] || die "두 계정 이름이 같습니다."
for p in "$rw_pw" "$ro_pw"; do
  case "$p" in *'"'*|*'\'*) die '비밀번호에 " 또는 \ 가 있습니다. .env 에서 바꾸세요.';; esac
done

kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s

# api METHOD PATH [본문은 표준입력]: 응답 본문 뒤에 마지막 줄로 HTTP 코드를 낸다. 비밀번호가 명령줄에 나오지 않도록 본문은 표준입력으로 넘긴다.
api() {
  kubectl -n "$NS" exec -i "$POD" -c opensearch -- sh -c \
    'curl -sk -w "\n%{http_code}" -X "$1" -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -H "Content-Type: application/json" --data-binary @- "https://localhost:9200$2"' sh "$1" "$2"
}
put() {
  local out code
  out=$(printf '%s' "$2" | api PUT "$1") || die "PUT $1 호출 실패"
  code=${out##*$'\n'}
  case "$code" in 200|201) ;; *) die "PUT $1 실패 (HTTP $code): ${out%$'\n'*}";; esac
}

# Dashboards 로그인용 kibana_user 역할은 백엔드 역할 kibanauser 에 매핑돼 있다고 알려져 있다. 기존 매핑을 덮어쓰지 않으려고
# 읽기 전용 계정에 그 백엔드 역할을 붙이는 방식을 쓴다. 매핑이 실제로 그런지 먼저 확인한다.
map=$(kubectl -n "$NS" exec "$POD" -c opensearch -- sh -c \
  'curl -sk -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" "https://localhost:9200/_plugins/_security/api/rolesmapping/kibana_user"')
echo "$map" | grep -q '"kibanauser"' \
  || die "kibana_user 역할이 백엔드 역할 kibanauser 에 매핑돼 있지 않습니다 (응답: $map). 이 스크립트의 가정이 틀렸으니 멈춥니다."

log "사용자, 역할, 매핑을 만듭니다 (인덱스 패턴: $INDEX_PATTERN)"
put "/_plugins/_security/api/internalusers/$rw_user" "{\"password\":\"$rw_pw\",\"attributes\":{}}"
put "/_plugins/_security/api/internalusers/$ro_user" "{\"password\":\"$ro_pw\",\"backend_roles\":[\"kibanauser\"],\"attributes\":{}}"
put /_plugins/_security/api/roles/guest_rw \
  "{\"cluster_permissions\":[\"cluster_composite_ops\"],\"index_permissions\":[{\"index_patterns\":[\"$INDEX_PATTERN\"],\"allowed_actions\":[\"indices_all\"]}]}"
put /_plugins/_security/api/roles/guest_ro \
  "{\"cluster_permissions\":[\"cluster_composite_ops_ro\"],\"index_permissions\":[{\"index_patterns\":[\"$INDEX_PATTERN\"],\"allowed_actions\":[\"read\"]}]}"
put /_plugins/_security/api/rolesmapping/guest_rw "{\"users\":[\"$rw_user\"]}"
put /_plugins/_security/api/rolesmapping/guest_ro "{\"users\":[\"$ro_user\"]}"

log "완료. 계정 이름과 비밀번호는 .env 의 OPENSEARCH_GUEST_RW_*, OPENSEARCH_GUEST_RO_* 에 있다. 검증: scripts/verify/09-3-opensearch-guests.sh"
