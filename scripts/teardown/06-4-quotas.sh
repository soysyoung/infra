#!/usr/bin/env bash
# 삭제 06-4. 프로필 네임스페이스의 ResourceQuota 제거 (Profile 의 spec.resourceQuotaSpec 삭제)
#
# Hard 가 비면 Profile 컨트롤러가 kf-resource-quota 를 지운다. 제한이 모두 없어진다:
# 두 번째 사용자의 GPU 0 제한도 풀려서 그 계정이 GPU 를 쓸 수 있게 된다. 다시 걸려면 06-4 를 실행한다.
# 클러스터 삭제(삭제 05)가 이 모두를 포함하므로 all.sh 에는 넣지 않았다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

confirm "프로필 네임스페이스의 ResourceQuota 를 모두 제거합니다 (두 번째 사용자의 GPU 0 제한도 풀립니다)."
while read -r ns _; do
  if kubectl get profile "$ns" >/dev/null 2>&1; then
    run kubectl patch profile "$ns" --type merge -p '{"spec":{"resourceQuotaSpec":null}}'
  else
    log "Profile $ns 가 없어 건너뜁니다."
  fi
done < <(quota_targets)
log "완료"
