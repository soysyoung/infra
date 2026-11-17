#!/usr/bin/env bash
# 11-1. PostgreSQL 백업 (pg_dump 커스텀 형식을 클러스터 밖 폴더에 저장)
#
# 왜: kind 의 PV 는 클러스터를 지우면 사라진다 (docs/todo.md 33번). 원본 데이터를 두기 전에 클러스터 밖에 복사본이 있어야 한다.
# 하는 일:
#   1) primary 파드에서 DB app 을 pg_dump -Fc 로 받아 BACKUP_DIR/postgres/app-<날짜시각>.dump 에 저장 (받는 도중에는 .part)
#   2) 받은 파일이 읽히는지 pg_restore -l 로 확인한 뒤에야 이름을 확정하고 sha256 을 남긴다
# 저장 위치: 기본은 이 저장소와 나란히 있는 backups/infra (BACKUP_DIR 로 바꿀 수 있다). 저장소 밖이라 커밋되지 않는다.
# 한계: DB app 하나만 받는다 (역할, 다른 DB 는 안 받는다: 역할은 CNPG 가 매니페스트로 다시 만든다). 오래된 백업은 지우지 않는다.
#
# 선행: 10-1-postgres.sh. 검증(실제 복원 시험 포함): scripts/verify/11-1-postgres-backup.sh
# 복원 방법: scripts/README.md '백업과 복원'
#
# 참고 (공식 문서): https://www.postgresql.org/docs/current/app-pgdump.html , https://www.postgresql.org/docs/current/app-pgrestore.html
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=postgres
BACKUP_DIR=${BACKUP_DIR:-$ROOT/../backups/infra}
mkdir -p "$BACKUP_DIR/postgres"
BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd)
# 상위 backups 폴더가 우연히 git 저장소 안에 들어가도 올라가지 않게 한다
[ -e "$BACKUP_DIR/../.gitignore" ] || echo '*' > "$BACKUP_DIR/../.gitignore"

kubectl -n "$NS" wait --for=condition=Ready cluster/postgres --timeout=120s >/dev/null
POD=$(kubectl -n "$NS" get pod -l cnpg.io/cluster=postgres,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')

out="$BACKUP_DIR/postgres/app-$(date +%Y%m%d-%H%M%S).dump"
trap 'rm -f "$out.part"' EXIT
kubectl -n "$NS" exec "$POD" -c postgres -- pg_dump -Fc -d app > "$out.part"
[ -s "$out.part" ] || die "받은 파일이 비었습니다."
kubectl -n "$NS" exec -i "$POD" -c postgres -- pg_restore -l < "$out.part" >/dev/null || die "받은 파일을 pg_restore 가 읽지 못합니다."
mv "$out.part" "$out"
(cd "$(dirname "$out")" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")

log "백업 완료: $out ($(du -h "$out" | cut -f1))"
