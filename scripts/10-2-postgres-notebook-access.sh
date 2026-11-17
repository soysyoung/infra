#!/usr/bin/env bash
# 10-2. Notebook 에 PostgreSQL 접속 정보를 환경변수로 넣는다 (Secret + PodDefault, 프로필 네임스페이스마다). 계정은 네임스페이스마다 다르다:
#   기본 사용자 네임스페이스(lib/quotas.sh 의 USER_PROFILE) -> 소유자 app (모든 권한)
#   그 밖(공유용 guest 등) -> notebook_rw (데이터 읽기/쓰기만, 테이블 생성/삭제 불가)
#
# 왜: 공유용 계정의 Notebook 에 DB 소유자(app) 비밀번호를 두지 않으려고. 설계와 근거는 docs/decisions/0022.
# 하는 일 (여러 번 실행해도 안전):
#   1) 비밀번호가 .env 에 없으면 만들어서 추가 (POSTGRES_NOTEBOOK_USER=notebook_rw, POSTGRES_NOTEBOOK_PASSWORD)
#   2) 네임스페이스 postgres 에 Secret postgres-notebook-rw 와 DatabaseRole notebook-rw (k8s/postgres-notebook-role.yaml) 를 적용하고 DB 에 역할이 생길 때까지 기다린다
#   3) 대상 네임스페이스마다 (06-4 와 같은 목록: 기본 사용자, .env 에 EXTRA_USER_EMAIL 이 있으면 두 번째 사용자)
#      Secret postgres-notebook 과 PodDefault postgres-notebook (k8s/postgres-notebook-poddefault.yaml) 을 적용한다
# 쓰는 법: Notebook 을 만들 때 Configurations 에서 'PostgreSQL 접속 정보' 를 고른다. 파드에 PGHOST, PGPORT, PGDATABASE,
#   PGUSER, PGPASSFILE 이 들어가고, 비밀번호는 환경변수가 아니라 password file 로 들어간다 (PostgreSQL 공식 문서는 PGPASSWORD 를 권하지 않는다).
#   이미 떠 있는 Notebook 은 재시작이 아니라 라벨이 없어서 안 들어간다: Notebook 을 새로 만들 때 고른다.
# 권한: app = DB 소유자(전부). notebook_rw = DB 안 모든 테이블의 데이터 읽기/쓰기만, 테이블 생성/삭제는 안 된다.
# 비밀번호를 바꾸려면 .env 를 고치고 이 스크립트를 다시 실행한다. Secret 라벨(cnpg.io/reload)이 있으면 바뀐 값이 DB 에 바로 반영된다고 공식 문서에 있으나 시험하지 않았다.
#
# 선행: 10-1 (Cluster), 06 (프로필 네임스페이스). 두 번째 사용자는 06-2. 검증: scripts/verify/10-2-postgres-notebook-access.sh
# 되돌리기: scripts/teardown/10-2-postgres-notebook-access.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/quotas.sh"   # quota_targets: 대상 프로필 목록만 쓴다

NS=postgres
ROLE=notebook_rw
ENV_FILE="$ROOT/.env"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" 2>/dev/null | tr -d '\r' | tail -1; }

kubectl -n "$NS" get cluster postgres >/dev/null 2>&1 || die "Cluster postgres 가 없습니다. scripts/10-1-postgres.sh 를 먼저 실행하세요."
app_pw=$(env_get POSTGRES_APP_PASSWORD)   # 기본 사용자 네임스페이스에 주입할 소유자 app 의 비밀번호 (10-1 이 만든다)
[ -n "$app_pw" ] || die ".env 에 POSTGRES_APP_PASSWORD 가 없습니다. scripts/10-1-postgres.sh 를 먼저 실행하세요."

# 무작위 32자 (영숫자만). 이미 .env 에 있으면 그대로 쓴다.
pw=$(env_get POSTGRES_NOTEBOOK_PASSWORD)
if [ -z "$pw" ]; then
  pw="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32)"
  { [ ! -s "$ENV_FILE" ] || [ -z "$(tail -c1 "$ENV_FILE")" ] || echo; echo "POSTGRES_NOTEBOOK_PASSWORD=$pw"; } >> "$ENV_FILE"
  log ".env 에 POSTGRES_NOTEBOOK_PASSWORD 를 만들었습니다."
fi
# 계정 이름은 k8s/postgres-notebook-role.yaml 의 spec.name 과 같아야 한다. 로그인할 때 보려고 적을 뿐 스크립트는 읽지 않는다.
grep -q '^POSTGRES_NOTEBOOK_USER=' "$ENV_FILE" || { [ -z "$(tail -c1 "$ENV_FILE")" ] || echo >> "$ENV_FILE"; echo "POSTGRES_NOTEBOOK_USER=$ROLE" >> "$ENV_FILE"; }

kubectl -n "$NS" create secret generic postgres-notebook-rw --type=kubernetes.io/basic-auth \
  --from-literal=username="$ROLE" --from-literal=password="$pw" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" label secret postgres-notebook-rw cnpg.io/reload=true --overwrite   # 비밀번호 변경을 바로 반영 (공식 문서)
kubectl apply -f "$ROOT/k8s/postgres-notebook-role.yaml"

POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
found=0
for _ in $(seq 30); do
  found=$(kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -Atc "select count(*) from pg_roles where rolname='$ROLE'" 2>/dev/null || true)
  [ "$found" = 1 ] && break
  sleep 2
done
[ "$found" = 1 ] || die "DB 에 역할 $ROLE 이 생기지 않았습니다 (kubectl -n $NS describe databaserole notebook-rw 로 확인)."
log "DB 에 역할 $ROLE 이 있음"

n=0
while read -r ns _; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    log "네임스페이스 $ns 가 아직 없어 건너뜁니다 (두 번째 사용자는 06-2-extra-user.sh 를 먼저 실행)."
    continue
  fi
  if [ "$ns" = "$USER_PROFILE" ]; then u=app; p=$app_pw; else u=$ROLE; p=$pw; fi
  # password file 한 줄: 호스트:포트:DB:사용자:비밀번호. 값 안의 ':' 와 '\' 는 '\' 로 이스케이프한다 (PostgreSQL 문서 32.16)
  pgpass="postgres-rw.postgres.svc:5432:app:$u:$(printf '%s' "$p" | sed 's/[\\:]/\\&/g')"
  kubectl -n "$ns" create secret generic postgres-notebook \
    --from-literal=username="$u" --from-literal=password="$p" --from-literal=pgpass="$pgpass" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" apply -f "$ROOT/k8s/postgres-notebook-poddefault.yaml"
  log "$ns: 계정 $u"
  n=$((n + 1))
done < <(quota_targets)
[ "$n" -gt 0 ] || die "대상 네임스페이스가 하나도 없습니다. 06-kubeflow.sh 가 끝났는지 확인하세요."

log "완료 ($n 개 네임스페이스). 검증: scripts/verify/10-2-postgres-notebook-access.sh"
log "Notebook 을 만들 때 Configurations 에서 'PostgreSQL 접속 정보' 를 고르세요. 떠 있는 Notebook 은 재시작해야 반영됩니다."
