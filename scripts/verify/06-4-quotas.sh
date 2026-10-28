#!/usr/bin/env bash
# 06-4 검증: 각 프로필 네임스페이스의 kf-resource-quota 가 quotas.env 와 같은가, GPU 합계 경고
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

quota_check

# 네임스페이스의 kf-resource-quota 값을 "pods storage gpu" 로 (없는 키는 '-')
hard_of() {
  local k v out=()
  for k in "${QUOTA_KEYS[@]}"; do
    v=$(kubectl -n "$1" get resourcequota kf-resource-quota -o "jsonpath={.spec.hard.${k//./\\.}}" 2>/dev/null || true)
    out+=("${v:--}")
  done
  echo "${out[*]}"
}

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
log "OK"
