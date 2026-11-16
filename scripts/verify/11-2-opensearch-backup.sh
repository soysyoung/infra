#!/usr/bin/env bash
# 11-2 검증: 스냅샷을 찍어 클러스터 밖으로 꺼내고, 그 파일만으로 실제로 복원해 본다.
#   1) path.repo 가 /mnt/snapshots 로 적용됐는지 (환경변수 path.repo 를 이미지가 설정으로 읽는지)
#   2) 시험 인덱스 backup-canary 에 문서 1개(v='canary-<초>')를 넣는다
#   3) 11-2-opensearch-backup.sh 를 임시 폴더와 시험 전용 스냅샷 이름으로 실행한다 (실제 백업 폴더에는 이 시험 백업을 남기지 않는다)
#   4) 시험 인덱스를 지우고, 꺼낸 tar 를 파드의 다른 디렉터리에 풀어 별도 저장소 verify-fs 로 등록한 뒤
#      restored-backup-canary 라는 이름으로 복원해 같은 값이 읽히는지 본다
#   5) 시험 인덱스, 저장소 등록, 시험 스냅샷, 푼 디렉터리, 임시 폴더를 지운다 (실패해도 지운다)
# 실제 백업 파일이 있으면 마지막으로 sha256 만 확인한다 (읽기 전용).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

NS=opensearch
POD=opensearch-cluster-master-0
os() { kubectl -n "$NS" exec "$POD" -c opensearch -- sh -c 'curl -sk -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -H "Content-Type: application/json" "$@"' sh "$@"; }
U=https://localhost:9200

kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=120s >/dev/null
os "$U/_nodes/settings?filter_path=nodes.*.settings.path.repo" | grep -q '/mnt/snapshots' \
  || die "path.repo 가 적용되어 있지 않습니다. 새 버전의 09-1-opensearch.sh 를 다시 실행하세요 (환경변수 path.repo 를 이미지가 읽지 않는 경우에도 이렇게 보입니다)."
log "path.repo=/mnt/snapshots 적용됨"

TMP=$(mktemp -d)
snap="verify-$(date +%s)"
cleanup() {
  os -X DELETE "$U/backup-canary,restored-backup-canary?ignore_unavailable=true" >/dev/null 2>&1 || true
  os -X DELETE "$U/_snapshot/verify-fs" >/dev/null 2>&1 || true
  os -X DELETE "$U/_snapshot/local-fs/$snap" >/dev/null 2>&1 || true
  kubectl -n "$NS" exec "$POD" -c opensearch -- rm -rf /mnt/snapshots/verify-restore >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

val="canary-$(date +%s)"
r=$(os -X PUT "$U/backup-canary/_doc/1?refresh=true" -d "{\"v\":\"$val\"}")
echo "$r" | grep -q -E '"result":"(created|updated)"' || die "시험 문서를 넣지 못했습니다: $r"

SNAPSHOT_NAME="$snap" BACKUP_DIR="$TMP" bash "$(dirname "$0")/../11-2-opensearch-backup.sh" >/dev/null
tarf="$TMP/opensearch/$snap.tar"
[ -s "$tarf" ] || die "백업 파일이 만들어지지 않았습니다."
(cd "$TMP/opensearch" && sha256sum -c "$snap.tar.sha256" >/dev/null) || die "sha256 이 맞지 않습니다."
log "백업 파일 생성, sha256 일치 ($(du -h "$tarf" | cut -f1))"

os -X DELETE "$U/backup-canary" >/dev/null
kubectl -n "$NS" exec -i "$POD" -c opensearch -- sh -c 'rm -rf /mnt/snapshots/verify-restore && mkdir -p /mnt/snapshots/verify-restore && tar -C /mnt/snapshots/verify-restore -xf -' < "$tarf"
r=$(os -X PUT "$U/_snapshot/verify-fs" -d '{"type":"fs","settings":{"location":"/mnt/snapshots/verify-restore/repo"}}')
echo "$r" | grep -q '"acknowledged":true' || die "복원용 저장소 등록 실패: $r"
r=$(os -X POST "$U/_snapshot/verify-fs/$snap/_restore?wait_for_completion=true" \
  -d '{"indices":"backup-canary","include_global_state":false,"rename_pattern":"(.+)","rename_replacement":"restored-$1"}')
echo "$r" | grep -q '"failed":0' || die "복원 실패: $r"
got=$(os "$U/restored-backup-canary/_doc/1")
echo "$got" | grep -q "\"v\":\"$val\"" || die "복원된 문서의 값이 다릅니다 (기대 $val): $got"
log "복원 확인: 꺼낸 tar 만으로 시험 인덱스가 복원되고 값이 같음"

REAL=${BACKUP_DIR:-$ROOT/../backups/infra}/opensearch
if ls "$REAL"/os-*.tar >/dev/null 2>&1; then
  (cd "$REAL" && sha256sum -c os-*.tar.sha256 >/dev/null) && log "실제 백업 $(ls "$REAL"/os-*.tar | wc -l)개의 sha256 일치" || die "실제 백업 중 sha256 이 맞지 않는 파일이 있습니다."
else
  log "실제 백업 파일은 아직 없습니다 (scripts/11-2-opensearch-backup.sh 를 실행하면 생깁니다)."
fi
log "OK"
