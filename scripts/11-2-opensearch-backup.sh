#!/usr/bin/env bash
# 11-2. OpenSearch 백업 (fs 스냅샷을 찍고, 저장소 디렉터리를 클러스터 밖 폴더로 꺼낸다)
#
# 왜: PV 는 클러스터를 지우면 사라진다 (docs/todo.md 33번, ADR 0023). 스냅샷 저장소는 파드 안의 /mnt/snapshots(emptyDir)라서
#     스냅샷만 찍어서는 같은 클러스터에 같이 사라진다. 그래서 찍자마자 tar 로 BACKUP_DIR/opensearch/ 에 꺼낸다.
# 하는 일:
#   1) path.repo 가 실제로 적용됐는지 확인 (09-1 을 새 버전으로 다시 실행하지 않았으면 여기서 멈춘다)
#   2) fs 저장소 local-fs 를 등록하고, 점으로 시작하는 시스템 인덱스를 뺀 모든 인덱스를 스냅샷으로 찍는다 (global state 제외)
#   3) 저장소 디렉터리를 tar 로 받아 읽히는지 확인한 뒤 이름을 확정하고 sha256 을 남긴다
# 한계: Dashboards 의 저장된 객체(인덱스 패턴 등, .kibana)와 보안 설정(.opendistro_security)은 받지 않는다. 공식 문서가 보안 인덱스를 스냅샷에서 빼라고 권한다.
#       파드가 다시 만들어지면 저장소가 비워지므로 그 뒤의 첫 스냅샷은 전체 복사다 (tar 는 매번 저장소 전체).
#
# 선행: 09-1-opensearch.sh (path.repo 와 볼륨이 들어 있는 버전). 검증(실제 복원 포함): scripts/verify/11-2-opensearch-backup.sh
# 복원 방법: scripts/README.md '백업과 복원'
#
# 참고 (공식 문서): https://docs.opensearch.org/latest/tuning-your-cluster/availability-and-recovery/snapshots/snapshot-restore/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=opensearch
POD=opensearch-cluster-master-0
BACKUP_DIR=${BACKUP_DIR:-$ROOT/../backups/infra}
mkdir -p "$BACKUP_DIR/opensearch"
BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd)
[ -e "$BACKUP_DIR/../.gitignore" ] || echo '*' > "$BACKUP_DIR/../.gitignore"

# curl 은 파드 안에서 실행한다 (파드의 OPENSEARCH_INITIAL_ADMIN_PASSWORD 를 쓰므로 비밀번호가 명령줄에 나오지 않는다)
os() { kubectl -n "$NS" exec "$POD" -c opensearch -- sh -c 'curl -sk -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -H "Content-Type: application/json" "$@"' sh "$@"; }

kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=120s >/dev/null
kubectl -n "$NS" exec "$POD" -c opensearch -- sh -c 'command -v tar >/dev/null' || die "OpenSearch 이미지에 tar 가 없습니다 (이 스크립트는 tar 로 저장소를 꺼냅니다)."
os 'https://localhost:9200/_nodes/settings?filter_path=nodes.*.settings.path.repo' | grep -q '/mnt/snapshots' \
  || die "path.repo 가 /mnt/snapshots 로 적용되어 있지 않습니다. 새 버전의 09-1-opensearch.sh 를 다시 실행하세요 (OpenSearch 가 재시작됩니다)."

snap=${SNAPSHOT_NAME:-os-$(date +%Y%m%d-%H%M%S)}
out="$BACKUP_DIR/opensearch/$snap.tar"
trap 'rm -f "$out.part"' EXIT

r=$(os -X PUT 'https://localhost:9200/_snapshot/local-fs' -d '{"type":"fs","settings":{"location":"/mnt/snapshots/repo"}}')
echo "$r" | grep -q '"acknowledged":true' || die "저장소 등록 실패: $r"
r=$(os -X PUT "https://localhost:9200/_snapshot/local-fs/$snap?wait_for_completion=true" \
  -d '{"indices":"*,-.*","ignore_unavailable":true,"include_global_state":false}')
echo "$r" | grep -q '"state":"SUCCESS"' || die "스냅샷이 SUCCESS 가 아닙니다: $r"
echo "$r" | grep -q '"failed":0' || die "실패한 샤드가 있습니다: $r"

kubectl -n "$NS" exec "$POD" -c opensearch -- tar -C /mnt/snapshots -cf - repo > "$out.part"
[ -s "$out.part" ] || die "받은 파일이 비었습니다."
tar -tf "$out.part" >/dev/null || die "받은 tar 가 읽히지 않습니다."
mv "$out.part" "$out"
(cd "$(dirname "$out")" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")

log "백업 완료: $out ($(du -h "$out" | cut -f1)), 스냅샷 이름 $snap"
