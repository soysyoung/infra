#!/usr/bin/env bash
# 10-2 검증:
#   1) DB 의 역할 notebook_rw: 로그인 가능, 슈퍼유저 아님, pg_read_all_data + pg_write_all_data 멤버
#   2) postgres-rw 서비스로 notebook_rw 접속: app 이 만든 시험 테이블을 읽고 쓰고 지울 수 있고, 테이블 생성은 거부된다 (시험 테이블은 지운다)
#   3) 대상 네임스페이스마다 Secret 이 기대한 계정과 .env 의 비밀번호와 같고 (기본 사용자 네임스페이스는 app, 그 밖은 notebook_rw),
#      PodDefault 가 있고, 레이블을 단 파드에 환경변수 5개가 주입된다 (서버 쪽 dry-run)
#   4) 실행 중인 Notebook 이 있으면 그 파드 안에서 postgres-rw 에 접속한다 (Istio 사이드카 경로 포함). Notebook 이미지에 psycopg2 가 없으면 TCP 연결까지만 본다
# 4번이 가장 중요하지만 Notebook 이 떠 있어야 한다. 없으면 건너뛰고 안내만 한다.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/quotas.sh"

NS=postgres
env_get() { sed -n "s/^$1=//p" "$ROOT/.env" 2>/dev/null | tr -d '\r' | tail -1; }
pw=$(env_get POSTGRES_NOTEBOOK_PASSWORD); user=notebook_rw
[ -n "$pw" ] || die ".env 에 POSTGRES_NOTEBOOK_PASSWORD 가 없습니다 (scripts/10-2-postgres-notebook-access.sh)."
app_pw=$(env_get POSTGRES_APP_PASSWORD)
[ -n "$app_pw" ] || die ".env 에 POSTGRES_APP_PASSWORD 가 없습니다 (scripts/10-1-postgres.sh)."

kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
app() { kubectl -n "$NS" exec "$POD" -c postgres -- psql -d app -v ON_ERROR_STOP=1 -Atc "$1"; }
nb() { kubectl -n "$NS" exec "$POD" -c postgres -- env PGPASSWORD="$pw" psql -h postgres-rw -U "$user" -d app -v ON_ERROR_STOP=1 -Atc "$1"; }
trap 'app "drop table if exists verify_nb, verify_nb_ddl" >/dev/null 2>&1 || true' EXIT

# 1) 역할 속성
[ "$(app "select rolcanlogin and not rolsuper from pg_roles where rolname='$user'")" = t ] || die "역할 $user 가 없거나 로그인 불가 또는 슈퍼유저입니다."
m=$(app "select count(*) from pg_auth_members m join pg_roles r on r.oid=m.roleid join pg_roles u on u.oid=m.member where u.rolname='$user' and r.rolname in ('pg_read_all_data','pg_write_all_data')")
[ "$m" = 2 ] || die "역할 $user 가 pg_read_all_data, pg_write_all_data 의 멤버가 아닙니다 (현재 $m 개)."
log "역할 $user: 로그인 가능, 슈퍼유저 아님, 읽기/쓰기 역할 2개의 멤버"

# 2) 서비스로 접속해 읽기/쓰기/DDL 거부
app 'drop table if exists verify_nb; create table verify_nb(id int primary key, v text); insert into verify_nb values (1, $$a$$)' >/dev/null
[ "$(nb 'select v from verify_nb where id=1')" = a ] || die "$user 가 app 이 쓴 값을 읽지 못했습니다."
nb 'insert into verify_nb values (2, $$b$$)' >/dev/null || die "$user 가 쓰지 못했습니다."
nb 'update verify_nb set v=$$c$$ where id=2' >/dev/null || die "$user 가 수정하지 못했습니다."
nb 'delete from verify_nb where id=2' >/dev/null || die "$user 가 지우지 못했습니다."
if nb 'create table verify_nb_ddl(i int)' >/dev/null 2>&1; then die "$user 가 테이블을 만들 수 있습니다 (DDL 은 막혀야 합니다)."; fi
log "postgres-rw 로 $user 접속: 읽기/쓰기 동작, 테이블 생성은 거부됨"

# Notebook 파드 안에서 실행하는 접속 시험 (표준입력으로 계정과 비밀번호를 받는다)
PYCHECK='
import sys, socket
u, p = (sys.stdin.readline().strip() for _ in range(2))
host = "postgres-rw.postgres.svc"
try:
    socket.create_connection((host, 5432), timeout=10).close()
except Exception as e:
    print("tcp-error:" + type(e).__name__); sys.exit()
try:
    import psycopg2 as pg
except ImportError:
    try:
        import psycopg as pg
    except ImportError:
        print("tcp-only"); sys.exit()
try:
    cur = pg.connect(host=host, dbname="app", user=u, password=p, connect_timeout=10).cursor()
    cur.execute("select current_user")
    print("ok:" + cur.fetchone()[0])
except Exception as e:
    print("auth-error:" + type(e).__name__)
'

# 3), 4) 네임스페이스별
checked=0; skipped=0; auth_skipped=0; inj_skipped=0
while read -r ns _; do
  kubectl get ns "$ns" >/dev/null 2>&1 || { log "$ns 가 없어 건너뜁니다."; continue; }
  checked=$((checked + 1))
  # 기대하는 계정: 기본 사용자 네임스페이스는 소유자 app, 그 밖은 notebook_rw
  if [ "$ns" = "$USER_PROFILE" ]; then eu=app; ep=$app_pw; else eu=$user; ep=$pw; fi

  su=$(kubectl -n "$ns" get secret postgres-notebook -o jsonpath='{.data.username}' 2>/dev/null | base64 -d) || die "$ns 에 Secret postgres-notebook 이 없습니다 (10-2)."
  sp=$(kubectl -n "$ns" get secret postgres-notebook -o jsonpath='{.data.password}' | base64 -d)
  [ "$su" = "$eu" ] && [ "$sp" = "$ep" ] || die "$ns 의 Secret 이 기대한 계정($eu)과 .env 의 비밀번호와 다릅니다 (10-2 를 다시 실행)."
  log "$ns: Secret 이 .env 의 $eu 와 같음"

  kubectl -n "$ns" get poddefault postgres-notebook >/dev/null 2>&1 || die "$ns 에 PodDefault postgres-notebook 이 없습니다 (10-2)."
  # 서버 쪽 dry-run: 변경 웹훅이 돌아야 환경변수가 보인다. generateName 은 apply 가 아니라 create 로만 쓸 수 있다.
  podyaml='{"apiVersion":"v1","kind":"Pod","metadata":{"generateName":"postgres-notebook-dryrun-","labels":{"postgres-notebook":"true"}},"spec":{"containers":[{"name":"c","image":"busybox","command":["true"]}]}}'
  if out=$(echo "$podyaml" | kubectl -n "$ns" create --dry-run=server -o yaml -f - 2>&1); then
    for v in PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD; do
      echo "$out" | grep -q "name: $v" || die "$ns: dry-run 파드에 $v 가 주입되지 않았습니다."
    done
    log "$ns: 레이블을 단 파드에 환경변수 5개가 주입됨 (dry-run)"
  else
    inj_skipped=$((inj_skipped + 1))
    log "$ns: 서버 dry-run 이 거부되어 주입 시험은 건너뜁니다: $(echo "$out" | tail -1)"
  fi

  # Notebook 파드 이름은 <이름>-0, 컨테이너 이름은 <이름>
  pod=$(kubectl -n "$ns" get pods -l notebook-name --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -z "$pod" ]; then
    skipped=$((skipped + 1)); log "$ns: 실행 중인 Notebook 이 없어 접속 시험을 건너뜁니다."; continue
  fi
  res=$(printf '%s\n%s\n' "$eu" "$ep" | kubectl -n "$ns" exec -i "$pod" -c "${pod%-0}" -- python3 -c "$PYCHECK" 2>/dev/null || echo "exec 실패")
  log "$ns: Notebook $pod 에서 postgres-rw 접속: $res"
  case "$res" in
    "ok:$eu") ;;
    tcp-only) auth_skipped=$((auth_skipped + 1));;
    auth-error:*) die "$ns: 인증 실패. .env 와 DB 의 $eu 비밀번호가 다릅니다 (10-2 다시 실행).";;
    *) die "$ns: Notebook 에서 postgres-rw:5432 에 닿지 못합니다 ($res). Istio 사이드카나 네트워크 정책을 확인하세요 (docs/decisions/0022).";;
  esac
done < <(quota_targets)

[ "$checked" -gt 0 ] || die "대상 네임스페이스가 없습니다."
if [ "$skipped" -gt 0 ]; then
  log "접속 시험을 건너뛴 네임스페이스가 $skipped 개 있습니다. Notebook 을 만들 때 'PostgreSQL 접속 정보' 를 고르고 다시 실행하거나, Notebook 셀에서 확인하세요:"
  echo '  import psycopg2; cur = psycopg2.connect("").cursor(); cur.execute("select current_user"); print(cur.fetchone())   # 설정은 PG* 환경변수에서 읽는다'
fi
[ "$inj_skipped" -eq 0 ] || die "환경변수 주입 시험을 $inj_skipped 개 네임스페이스에서 건너뛰었습니다 (위 메시지). 주입은 확인되지 않았습니다."
[ "$auth_skipped" -eq 0 ] || log "주의: Notebook $auth_skipped 개는 psycopg2 가 없어 TCP 연결까지만 확인했고 인증은 확인하지 못했습니다."
log "OK: 역할 권한이 맞고, Secret 과 PodDefault 가 맞고 환경변수가 주입된다 (Notebook 접속 시험: $((checked - skipped)) 개 중 인증까지 $((checked - skipped - auth_skipped)) 개)"
