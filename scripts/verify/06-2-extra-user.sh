#!/usr/bin/env bash
# 06-2 검증: 두 번째 사용자의 Dex 계정, Profile, 네임스페이스 권한, 할당량
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

email=$(sed -n 's/^EXTRA_USER_EMAIL=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r')
[ -n "$email" ] || { log ".env 에 EXTRA_USER_EMAIL 이 없어 검증할 것이 없습니다."; exit 0; }
name="kubeflow-$(echo "$email" | sed 's/[@._]/-/g')"

kubectl -n auth get cm dex -o jsonpath='{.data.config\.yaml}' | grep -q "email: $email" \
  || die "Dex 설정에 $email 이 없습니다."
kubectl -n auth get secret dex-passwords -o jsonpath='{.data.DEX_EXTRA_USER_PASSWORD}' | grep -q . \
  || die "dex-passwords 에 DEX_EXTRA_USER_PASSWORD 가 없습니다."
kubectl -n auth rollout status deploy/dex --timeout=60s

owner=$(kubectl get profile "$name" -o jsonpath='{.spec.owner.name}')
[ "$owner" = "$email" ] || die "Profile $name 의 소유자가 '$owner' 입니다."
kubectl get ns "$name" >/dev/null || die "네임스페이스 $name 이 없습니다."

# 소유자에게 자기 네임스페이스의 kubeflow-admin 이 붙었는가 (Profile 컨트롤러가 만든다. 몇 초 걸릴 수 있다).
for _ in $(seq 15); do
  kubectl -n "$name" get rolebinding namespaceAdmin -o jsonpath='{.roleRef.name} {.subjects[*].name}' 2>/dev/null \
    | grep -q "kubeflow-admin $email" && break
  sleep 2
done
kubectl -n "$name" get rolebinding namespaceAdmin -o jsonpath='{.roleRef.name} {.subjects[*].name}' | grep -q "kubeflow-admin $email" \
  || die "$name 의 namespaceAdmin 이 $email 에게 kubeflow-admin 을 주지 않습니다."

kubectl -n "$name" get resourcequota -o jsonpath='{.items[*].spec.hard}'; echo
log "OK: $email -> 네임스페이스 $name (소유자 권한, 할당량 적용). 로그인은 브라우저에서 확인하세요."
