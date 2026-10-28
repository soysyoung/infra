#!/usr/bin/env bash
# 06-4 검증: 각 프로필 네임스페이스의 kf-resource-quota 가 quotas.env 와 같은가, GPU 합계 경고
#
# 사용:  bash scripts/verify/06-4-quotas.sh             # 읽기 전용
#        bash scripts/verify/06-4-quotas.sh roundtrip   # 쿼터를 잠깐 바꾸는 시험 (아래). 끝나면 quotas.env 값으로 되돌린다
# roundtrip 이 보는 것 (ADR 0015 '미검증'):
#   A. 값을 바꾸면 기존 쿼터 객체가 갱신되고, 값을 비운 키는 사라지는가 (기본 사용자 네임스페이스, 임시 파일 QUOTAS_ENV 로 시험)
#   B. GPU 0 인 두 번째 사용자 네임스페이스에 GPU 파드를 서버 쪽 dry-run 으로 보내면 쿼터가 거부하는가 (저장되지 않는다)
#   E. 기본 사용자 네임스페이스에 한도보다 1개 많은 GPU 파드를 같은 방식으로 보내면 거부하는가
#   C, D. 06-2 를 다시 실행하면 두 번째 사용자의 쿼터가 어떻게 되고, 06-4 로 돌아오는가, 한 번 더 실행하면 지워지지 않는가
#      (.env 에 EXTRA_USER_* 가 있을 때만.
#      06-2 가 Dex 를 재시작하므로 로그인이 몇 초 끊기고, 쿼터가 지워진 동안 그 계정은 제한이 없다. Funnel 이 꺼져 있을 때 실행)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

# 네임스페이스의 kf-resource-quota 값을 "pods storage gpu" 로 (없는 키는 '-')
hard_of() {
  local k v out=()
  for k in "${QUOTA_KEYS[@]}"; do
    v=$(kubectl -n "$1" get resourcequota kf-resource-quota -o "jsonpath={.spec.hard.${k//./\\.}}" 2>/dev/null || true)
    out+=("${v:--}")
  done
  echo "${out[*]}"
}

check_all() {
  quota_check
  while read -r ns p s g; do
    if ! kubectl get profile "$ns" >/dev/null 2>&1; then
      [ "$ns" != "$USER_PROFILE" ] || die "Profile $ns 가 없습니다."
      log "Profile $ns 가 없어 건너뜁니다."
      continue
    fi
    want="$p $s $g"
    for _ in $(seq 15); do   # Profile 컨트롤러가 반영할 때까지 최대 30초
      got=$(hard_of "$ns"); [ "$got" = "$want" ] && break; sleep 2
    done
    [ "$got" = "$want" ] || die "$ns 의 kf-resource-quota 가 '$got' 입니다 (기대 '$want': pods storage gpu, - 는 제한 없음)."
    log "$ns: $got (pods storage gpu)"
    kubectl -n "$ns" get resourcequota kf-resource-quota 2>/dev/null || true
  done < <(quota_targets)
}

# 네임스페이스에 GPU <개수> 파드를 서버 쪽 dry-run 으로 보내 쿼터가 거부하는지 본다 (저장되지 않음). 인자: <네임스페이스> <개수> <라벨>
reject_check() {
  local out
  out=$(kubectl -n "$1" create --dry-run=server -f - 2>&1 <<EOF || true
apiVersion: v1
kind: Pod
metadata:
  generateName: quota-reject-test-
spec:
  containers:
  - name: c
    image: busybox
    command: ["sleep", "1"]
    resources:
      limits:
        nvidia.com/gpu: "$2"
EOF
)
  case "$out" in
    *"exceeded quota"*) log "$3 통과: 쿼터가 거부했다" ;;
    *) log "$3 판정 불가: 거부 사유에 'exceeded quota' 가 없다 (쿼터가 막지 못하는지, 다른 이유로 거부됐는지 구분하지 못함). 응답:"; echo "$out" | head -5 ;;
  esac
}

if [ "${1:-}" != roundtrip ]; then check_all; log "OK"; exit 0; fi

# --- roundtrip ---
confirm "기본 사용자 네임스페이스의 쿼터를 잠깐 바꾸고(GPU 3->2 등), .env 에 두 번째 사용자가 있으면 06-2 를 실행합니다(로그인 몇 초 끊김)."
check_all   # 시작 상태가 quotas.env 와 같아야 의미가 있다
tmp=$(mktemp)
restore() { rm -f "$tmp"; log "복원: 06-4 를 quotas.env 값으로 다시 실행"; bash "$ROOT/scripts/06-4-quotas.sh" >/dev/null || echo "경고: 복원 실패. 직접 scripts/06-4-quotas.sh 를 실행하세요." >&2; }
trap restore EXIT

# quotas.env 에 덮어쓸 값을 더한 임시 파일로 06-4 를 실행하고, 같은 파일로 읽기 전용 검증을 한다.
try_env() { cp "$ROOT/quotas.env" "$tmp"; printf '%s\n' "$@" >> "$tmp"; QUOTAS_ENV=$tmp bash "$ROOT/scripts/06-4-quotas.sh" >/dev/null && QUOTAS_ENV=$tmp bash "$0"; }

log "A1 갱신: 기본 사용자 GPU 3->2, pods 비제한->50, 스토리지 비제한->30Gi"
try_env QUOTA_USER_GPU=2 QUOTA_USER_PODS=50 QUOTA_USER_STORAGE=30Gi
log "A2 비운 키: pods 를 다시 비운다 (기대: pods 가 '-' 로 사라짐)"
try_env QUOTA_USER_GPU=2 QUOTA_USER_PODS= QUOTA_USER_STORAGE=30Gi
bash "$ROOT/scripts/06-4-quotas.sh" >/dev/null && check_all   # E 는 quotas.env 의 실제 한도로 시험한다
log "A 통과"

if [[ ${QUOTA_USER_GPU:-} =~ ^[0-9]+$ ]]; then
  log "E 거부: 기본 사용자 네임스페이스에 GPU $((QUOTA_USER_GPU + 1))개 파드 (한도 $QUOTA_USER_GPU 를 넘김)"
  reject_check "$USER_PROFILE" $((QUOTA_USER_GPU + 1)) E
else
  log "E 건너뜀: QUOTA_USER_GPU 가 비어 있어 한도가 없다."
fi

guest=$(quota_targets | awk 'NR==2 {print $1}')
if [ -z "$guest" ] || ! kubectl get profile "$guest" >/dev/null 2>&1; then
  log "B, C, D 건너뜀: 두 번째 사용자 Profile 이 없습니다."
else
  log "B 거부: $guest (GPU 0) 에 GPU 1개 파드를 서버 쪽 dry-run 으로 보낸다"
  reject_check "$guest" 1 B

  if [ -n "$(sed -n 's/^EXTRA_USER_PASSWORD=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r')" ]; then
    log "C 순서: 06-2 를 다시 실행한다"
    bash "$ROOT/scripts/06-2-extra-user.sh"
    for _ in $(seq 15); do [ "$(hard_of "$guest")" = "- - -" ] && break; sleep 2; done
    log "C 06-2 직후 $guest 쿼터: $(hard_of "$guest")  (- - - 이면 지워짐. 이미 한 번 새 06-2 를 실행했다면 남아 있는 것이 정상)"
    bash "$ROOT/scripts/06-4-quotas.sh" >/dev/null
    check_all
    log "C 통과: 06-4 뒤 quotas.env 값으로 돌아왔다"

    log "D 06-2 를 한 번 더 실행한다 (기대: 이제 쿼터가 지워지지 않는다. 06 이 끝에서 매번 06-2 를 부르는 경로)"
    bash "$ROOT/scripts/06-2-extra-user.sh" >/dev/null
    sleep 10   # 지워진다면 컨트롤러가 몇 초 안에 지운다
    [ "$(hard_of "$guest")" != "- - -" ] || die "D 실패: 06-2 를 두 번째로 실행해도 $guest 의 쿼터가 지워졌습니다. 06-2 뒤에는 항상 06-4 를 실행해야 합니다."
    check_all
    log "D 통과: 06-2 재실행 뒤에도 쿼터가 남았다"
  else
    log "C 건너뜀: .env 에 EXTRA_USER_PASSWORD 가 없어 06-2 가 아무것도 하지 않는다."
  fi
fi

restore; trap - EXIT
check_all
log "OK (roundtrip)"
