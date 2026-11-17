#!/usr/bin/env bash
# 09-2 검증: Deployment 사용 가능 -> Dashboards 가 OpenSearch 에 로그인해 저장 객체를 읽는지 (200)
# curl 은 OpenSearch 파드 안에서 실행한다 (verify/09-1 과 같은 방식. 비밀번호가 명령줄에 나오지 않는다).
# /api/saved_objects/_find 는 Dashboards 가 OpenSearch 의 .kibana 인덱스를 읽어야 200 이므로 연결과 인증까지 시험한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=opensearch
POD=opensearch-cluster-master-0
kubectl -n "$NS" rollout status deploy/opensearch-dashboards --timeout=300s

URL=http://opensearch-dashboards.$NS.svc:5601/api/saved_objects/_find?type=config\&per_page=1
code=000
# 시작 직후 약 1분은 503 이 나온다 (공식 문서). 10초 간격으로 5분까지 다시 시도한다.
for _ in $(seq 30); do
  code=$(kubectl -n "$NS" exec "$POD" -- sh -c 'curl -s -o /dev/null -w "%{http_code}" -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" "$1"' sh "$URL" || true)
  [ "$code" = 200 ] && break
  sleep 10
done
log "저장 객체 조회 응답 코드: $code"
[ "$code" = 200 ] || die "Dashboards 가 OpenSearch 에서 읽지 못했습니다 (파드 로그: kubectl -n $NS logs deploy/opensearch-dashboards)."

# port-forward 서비스(09-2 가 만든다): 서비스가 살아 있고 127.0.0.1:5601 이 응답하는지. 로그인 화면은 보통 200 이나 302 로 온다.
systemctl is-active --quiet opensearch-dashboards-port-forward \
  || die "port-forward 서비스가 실행 중이 아닙니다 (journalctl -u opensearch-dashboards-port-forward)."
lcode=000
for _ in $(seq 12); do
  lcode=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:5601/ || true)
  case "$lcode" in 200|302) break;; esac
  sleep 5
done
log "127.0.0.1:5601 응답 코드: $lcode"
case "$lcode" in 200|302) ;; *) die "127.0.0.1:5601 이 응답하지 않습니다 (journalctl -u opensearch-dashboards-port-forward).";; esac

log "OK: Dashboards 가 OpenSearch 에 연결되어 로그인된 요청을 처리하고, 127.0.0.1:5601 port-forward 서비스가 응답"
