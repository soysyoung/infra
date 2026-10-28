#!/usr/bin/env bash
# 06-2. 두 번째 Kubeflow 사용자 추가: Dex 로그인 계정 + Profile(네임스페이스, 권한)
#
# 왜: 외부 공유(Funnel)에서 관리자 계정(user@example.com)과 분리된 계정과 네임스페이스를 주려고.
# 하는 일 (여러 번 실행해도 안전, .env 에 값이 없으면 건너뜀):
#   1) Dex 의 staticPasswords 에 사용자를 추가한다 (hashFromEnv, 비밀번호는 dex-passwords 시크릿의 새 키)
#   2) dex 를 재시작한다 (설정과 환경변수는 시작할 때만 읽는다)
#   3) Profile 을 만든다: 소유자는 이 사용자, 네임스페이스는 소유자에게만 kubeflow-admin 권한.
#      할당량은 여기서 걸지 않는다: 06-4-quotas.sh 가 모든 프로필의 할당량을 맡는다 (quotas.env).
#      이전 버전이 Profile 에 넣어 둔 resourceQuotaSpec 은 이 apply 가 지우므로 06-4 를 이어서 실행한다.
# 06 이 Dex 설정을 매번 기본값으로 되돌리므로 06 이 끝에서 이 스크립트를 부른다.
#
# 설정: 저장소 루트 .env (git 제외)
#   EXTRA_USER_EMAIL=guest@example.com     # 소문자 이메일 형식이면 된다 (실제 메일일 필요 없음)
#   EXTRA_USER_PASSWORD=...                # 12자 이상
#
# 선행: 06-kubeflow.sh, python3-bcrypt
# 검증: scripts/verify/06-2-extra-user.sh
#
# 참고 (공식 문서):
#   - Profile: https://www.kubeflow.org/docs/components/central-dash/profiles/
#   - Dex 정적 비밀번호: https://dexidp.io/docs/connectors/local/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

env_val() { sed -n "s/^$1=//p" "$ROOT/.env" 2>/dev/null | tr -d '\r'; }
email=$(env_val EXTRA_USER_EMAIL); pw=$(env_val EXTRA_USER_PASSWORD)
if [ -z "$email" ] || [ -z "$pw" ]; then
  log ".env 에 EXTRA_USER_EMAIL, EXTRA_USER_PASSWORD 가 없어 두 번째 사용자는 건너뜁니다."
  exit 0
fi
[[ "$email" =~ ^[a-z0-9._-]+@[a-z0-9.-]+$ ]] || die "EXTRA_USER_EMAIL 은 소문자 이메일 형식이어야 합니다 (현재: '$email')."
[ "${#pw}" -ge 12 ] || die "EXTRA_USER_PASSWORD 는 12자 이상이어야 합니다."
python3 -c 'import bcrypt' 2>/dev/null || die "python3-bcrypt 가 필요합니다. sudo apt install python3-bcrypt"
# Profile 이름이 곧 네임스페이스 이름이다 (DNS 라벨, 63자 이하). 기본 사용자의 kubeflow-user-example-com 과 같은 규칙.
name="kubeflow-$(echo "$email" | sed 's/[@._]/-/g')"   # 위 정규식이 소문자만 허용한다
[ "${#name}" -le 63 ] || die "이메일이 너무 길어 네임스페이스 이름($name)이 63자를 넘습니다."
[ "$email" != user@example.com ] || die "EXTRA_USER_EMAIL 이 기본 사용자와 같습니다."

# 1) Dex 로그인 계정. 같은 이메일이 이미 있으면 설정은 그대로 두고 비밀번호만 갱신한다.
hash=$(PW="$pw" python3 -c 'import bcrypt,os;print(bcrypt.hashpw(os.environ["PW"].encode(),bcrypt.gensalt(12)).decode().replace("$2b$","$2y$",1))')
kubectl -n auth patch secret dex-passwords -p "{\"stringData\":{\"DEX_EXTRA_USER_PASSWORD\":\"$hash\"}}"
cfg=$(kubectl -n auth get cm dex -o jsonpath='{.data.config\.yaml}')
patch=$(CFG="$cfg" EMAIL="$email" python3 - <<'PY'
import hashlib, json, os
cfg, email = os.environ["CFG"], os.environ["EMAIL"]
if "email: " + email not in cfg:
    uid = str(int(hashlib.sha256(email.encode()).hexdigest()[:14], 16))   # 이메일마다 고정된 userID
    entry = f'- email: {email}\n  hashFromEnv: DEX_EXTRA_USER_PASSWORD\n  username: {email.split("@")[0]}\n  userID: "{uid}"\n'
    assert "staticPasswords:\n" in cfg, "dex 설정에 staticPasswords 가 없습니다"
    cfg = cfg.replace("staticPasswords:\n", "staticPasswords:\n" + entry, 1)
print(json.dumps({"data": {"config.yaml": cfg}}))
PY
)
kubectl -n auth patch cm dex --type merge -p "$patch"

# 2) 설정과 환경변수는 시작할 때만 읽는다.
kubectl -n auth rollout restart deploy/dex
kubectl -n auth rollout status deploy/dex --timeout=180s

# 3) 사용자의 네임스페이스와 권한. 소유자에게 자기 네임스페이스의 kubeflow-admin 이 붙고, 다른 네임스페이스에는 아무 권한이 없다.
kubectl apply -f - <<EOF
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: $name
spec:
  owner:
    kind: User
    name: $email
EOF

log "완료: $email -> 네임스페이스 $name.  검증: scripts/verify/06-2-extra-user.sh"
log "할당량은 06-4-quotas.sh 가 건다. 그 전까지 이 계정은 할당량이 없다 (GPU 도 제한 없음)."
