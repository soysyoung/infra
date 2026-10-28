#!/usr/bin/env bash
# 06-4, verify/06-4, teardown/06-4 가 공유한다. common.sh 다음에 'source "$(dirname "$0")/lib/quotas.sh"' 로 읽는다.
# shellcheck source=/dev/null
source "${QUOTAS_ENV:-$ROOT/quotas.env}"   # QUOTAS_ENV 는 verify/06-4 roundtrip 이 임시 값을 시험할 때만 쓴다

QUOTA_KEYS=(pods requests.storage requests.nvidia.com/gpu)
USER_PROFILE=kubeflow-user-example-com

# 대상 프로필을 한 줄씩: <이름> <pods> <storage> <gpu>. 값이 비면 '-' (제한 없음). Profile 이름이 곧 네임스페이스 이름이다.
# 두 번째 사용자는 .env 에 EXTRA_USER_EMAIL 이 있을 때만 (이름 규칙은 06-2 와 같다).
quota_targets() {
  echo "$USER_PROFILE ${QUOTA_USER_PODS:--} ${QUOTA_USER_STORAGE:--} ${QUOTA_USER_GPU:--}"
  local email
  email=$(sed -n 's/^EXTRA_USER_EMAIL=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r')
  [ -z "$email" ] || echo "kubeflow-$(echo "$email" | sed 's/[@._]/-/g') ${QUOTA_EXTRA_PODS:--} ${QUOTA_EXTRA_STORAGE:--} ${QUOTA_EXTRA_GPU:--}"
}

# 값 형식과 GPU 합계를 본다. 합계 초과는 경고만 한다 (쿼터는 합계를 막지 못한다).
quota_check() {
  local sum=${QUOTA_GPU_RESERVED:-0} unlimited="" ns p s g
  [[ $sum =~ ^[0-9]+$ ]] || die "QUOTA_GPU_RESERVED 는 정수여야 합니다 (현재: '$sum')."
  while read -r ns p s g; do
    [[ $p == - || $p =~ ^[0-9]+$ ]]          || die "$ns 의 pods 는 정수여야 합니다 (현재: '$p')."
    [[ $s == - || $s =~ ^[0-9]+([KMGT]i)?$ ]] || die "$ns 의 스토리지는 '20Gi' 형식이어야 합니다 (현재: '$s')."
    [[ $g == - || $g =~ ^[0-9]+$ ]]          || die "$ns 의 GPU 는 정수여야 합니다 (현재: '$g')."
    if [ "$g" = - ]; then unlimited="$unlimited $ns"; else sum=$((sum + g)); fi
  done < <(quota_targets)
  log "GPU 배분 합계 $sum (예약 ${QUOTA_GPU_RESERVED:-0} 포함) / 광고 $GPU_REPLICAS"
  [ "$sum" -le "$GPU_REPLICAS" ] || echo "경고: GPU 배분 합계 $sum 이 광고 개수 $GPU_REPLICAS 를 넘습니다. 쿼터는 합계를 막지 못하고 늦게 뜬 파드가 Pending 이 됩니다." >&2
  [ -z "$unlimited" ] || echo "경고: GPU 를 제한하지 않는 프로필이 있습니다:$unlimited" >&2
  return 0
}
