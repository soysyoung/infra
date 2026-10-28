#!/usr/bin/env bash
# 06-4. 프로필 네임스페이스의 ResourceQuota (기본 사용자, 두 번째 사용자)
#
# 왜: 할당량의 담당을 이 스크립트 하나로 모은다. 값은 저장소 루트 quotas.env.
# 하는 일 (여러 번 실행해도 안전):
#   Profile 의 spec.resourceQuotaSpec.hard 를 quotas.env 대로 맞춘다. 네임스페이스의 kf-resource-quota 는 Profile 컨트롤러가
#   이 값으로 만들고 갱신한다 (직접 고치면 되돌린다). 값을 비우면 그 키를 지우고, 키가 모두 없으면 컨트롤러가 쿼터를 삭제한다.
# 06 이 끝에서 이 스크립트를 부른다. 06-2 는 더 이상 할당량을 건드리지 않는다 (담당이 둘이 되지 않게).
#
# 순서: 06 -> 06-2 -> 06-4. 06-2 는 Profile 을 만들기만 하므로 06-4 를 실행하기 전의 두 번째 사용자는 할당량이 없다.
# GPU 합계가 cluster.env 의 GPU_REPLICAS 를 넘으면 경고한다. GPU 값은 개수 배분일 뿐 VRAM 보호가 아니다 (quotas.env 주석, ADR 0013).
# 선행: 06-kubeflow.sh (기본 사용자 Profile), 두 번째 사용자는 06-2-extra-user.sh. 검증: scripts/verify/06-4-quotas.sh
# 되돌리기: scripts/teardown/06-4-quotas.sh
#
# 참고 (공식 문서·소스):
#   - 확장 리소스 쿼터는 requests. 접두만 허용: https://kubernetes.io/docs/concepts/policy/resource-quotas/#quota-for-extended-resources
#   - Profile 컨트롤러가 Hard 가 비면 kf-resource-quota 를 지운다: kubeflow/dashboard profile_controller.go (main 브랜치. 설치한 26.03.1 태그는 미대조)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/quotas.sh"

quota_check

val() { if [ "$1" = - ]; then echo null; else echo "\"$1\""; fi; }   # JSON merge patch 에서 null 은 키 삭제

while read -r ns p s g; do
  if ! kubectl get profile "$ns" >/dev/null 2>&1; then
    [ "$ns" != "$USER_PROFILE" ] || die "Profile $ns 가 없습니다. 06-kubeflow.sh 가 끝났는지 확인하세요."
    log "Profile $ns 가 아직 없어 건너뜁니다 (06-2-extra-user.sh 를 먼저 실행)."
    continue
  fi
  # 세 키를 항상 명시해서, quotas.env 에서 값을 지운 키가 Profile 에 남지 않게 한다.
  kubectl patch profile "$ns" --type merge -p \
    "{\"spec\":{\"resourceQuotaSpec\":{\"hard\":{\"pods\":$(val "$p"),\"requests.storage\":$(val "$s"),\"requests.nvidia.com/gpu\":$(val "$g")}}}}"
done < <(quota_targets)

log "완료. 컨트롤러가 반영하는 데 몇 초 걸립니다.  검증: scripts/verify/06-4-quotas.sh"
