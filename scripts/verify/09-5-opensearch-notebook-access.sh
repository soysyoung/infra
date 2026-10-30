#!/usr/bin/env bash
# 09-5 검증: 대상 네임스페이스마다
#   1) Secret opensearch-guest 가 .env 의 guest-rw 와 같다
#   2) PodDefault opensearch-guest 가 있고, 레이블을 단 파드에 환경변수가 주입된다 (서버 쪽 dry-run, 파드를 만들지 않는다)
#   3) 실행 중인 Notebook 이 있으면 그 파드 안에서 OpenSearch 에 guest-rw 로 접속해 200 을 받는다 (Istio 사이드카 경로 포함)
# 3번이 가장 중요하지만 Notebook 이 떠 있어야 한다. 없으면 건너뛰고 안내만 한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

env_get() { sed -n "s/^$1=//p" "$ROOT/.env" 2>/dev/null | tr -d '\r' | tail -1; }
user=$(env_get OPENSEARCH_GUEST_RW_USER); pw=$(env_get OPENSEARCH_GUEST_RW_PASSWORD)
[ -n "$user" ] && [ -n "$pw" ] || die ".env 에 guest-rw 계정이 없습니다 (09-3)."

# 3번의 요청 경로: guest-rw 가 접근하는 인덱스 패턴 (역할이 단일 출처). admin 으로 읽는다.
pat=$(kubectl -n opensearch exec opensearch-cluster-master-0 -c opensearch -- sh -c \
  'curl -sk -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" https://localhost:9200/_plugins/_security/api/roles/guest_rw' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["guest_rw"]["index_permissions"][0]["index_patterns"][0])') \
  || die "guest_rw 역할을 읽지 못했습니다 (09-3)."

checked=0; skipped=0
while read -r ns _; do
  kubectl get ns "$ns" >/dev/null 2>&1 || { log "$ns 가 없어 건너뜁니다."; continue; }
  checked=$((checked + 1))

  # 1) Secret
  su=$(kubectl -n "$ns" get secret opensearch-guest -o jsonpath='{.data.username}' 2>/dev/null | base64 -d) || die "$ns 에 Secret opensearch-guest 가 없습니다 (09-5)."
  sp=$(kubectl -n "$ns" get secret opensearch-guest -o jsonpath='{.data.password}' | base64 -d)
  [ "$su" = "$user" ] && [ "$sp" = "$pw" ] || die "$ns 의 Secret 이 .env 의 guest-rw 와 다릅니다 (09-5 를 다시 실행)."
  log "$ns: Secret 이 .env 의 guest-rw 와 같음"

  # 2) PodDefault 와 주입 (서버 쪽 dry-run: 변경 웹훅이 돌아야 환경변수가 보인다)
  kubectl -n "$ns" get poddefault opensearch-guest >/dev/null 2>&1 || die "$ns 에 PodDefault opensearch-guest 가 없습니다 (09-5)."
  if out=$(kubectl -n "$ns" apply --dry-run=server -o yaml -f - 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata:
  generateName: opensearch-guest-dryrun-
  labels:
    opensearch-guest: "true"
spec:
  containers:
    - name: c
      image: busybox
      command: ["true"]
EOF
  ); then
    for v in OPENSEARCH_URL OPENSEARCH_USER OPENSEARCH_PASSWORD; do
      echo "$out" | grep -q "name: $v" || die "$ns: dry-run 파드에 $v 가 주입되지 않았습니다."
    done
    log "$ns: 레이블을 단 파드에 환경변수 3개가 주입됨 (dry-run)"
  else
    log "$ns: 서버 dry-run 이 거부되어 주입 시험은 건너뜁니다: $(echo "$out" | tail -1)"
  fi

  # 3) 실행 중인 Notebook 에서 접속 (Notebook 파드 이름은 <이름>-0, 컨테이너 이름은 <이름>)
  pod=$(kubectl -n "$ns" get pods -l notebook-name --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -z "$pod" ]; then
    skipped=$((skipped + 1)); log "$ns: 실행 중인 Notebook 이 없어 접속 시험을 건너뜁니다."; continue
  fi
  code=$(printf '%s\n%s\n%s\n' "$user" "$pw" "$pat" | kubectl -n "$ns" exec -i "$pod" -c "${pod%-0}" -- python3 -c '
import sys, ssl, base64, urllib.request, urllib.error
u, p, pat = (sys.stdin.readline().strip() for _ in range(3))
req = urllib.request.Request("https://opensearch-cluster-master.opensearch.svc:9200/" + pat + "/_search?size=0")
req.add_header("Authorization", "Basic " + base64.b64encode((u + ":" + p).encode()).decode())
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
try:
    print(urllib.request.urlopen(req, context=ctx, timeout=10).status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception as e:
    print("error:" + type(e).__name__)
' 2>/dev/null || echo "exec 실패")
  log "$ns: Notebook $pod 에서 guest-rw 로 /$pat/_search 응답: $code"
  case "$code" in
    200) ;;
    401) die "$ns: 인증 실패(401). .env 와 OpenSearch 의 guest-rw 비밀번호가 다릅니다 (09-3 다시 실행).";;
    403) die "$ns: 권한 거부(403). guest_rw 역할을 확인하세요.";;
    *)   die "$ns: Notebook 에서 OpenSearch 에 닿지 못합니다 ($code). Istio 사이드카나 네트워크 정책을 확인하세요 (docs/decisions/0020).";;
  esac
done < <(quota_targets)

[ "$checked" -gt 0 ] || die "대상 네임스페이스가 없습니다."
if [ "$skipped" -gt 0 ]; then
  log "접속 시험을 건너뛴 네임스페이스가 $skipped 개 있습니다. Notebook 을 만들 때 'OpenSearch guest-rw 접속 정보' 를 고르고 아래를 실행해 확인하세요:"
  echo '  import os, requests; print(requests.get(os.environ["OPENSEARCH_URL"] + "/temp-*/_search?size=0", auth=(os.environ["OPENSEARCH_USER"], os.environ["OPENSEARCH_PASSWORD"]), verify=False).status_code)'
fi
log "OK: Secret 과 PodDefault 가 맞고 환경변수가 주입된다 (접속 시험: 실행한 Notebook $((checked - skipped)) 개)"
