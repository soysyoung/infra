# 0023. 백업 위치: 저장소 옆의 Windows 디스크 폴더

- 상태: 일부 적용 (2026-11-16). PostgreSQL 쪽 스크립트(`11-1`, `verify/11-1`)는 작성했고 **아직 실행하지 않았다**. OpenSearch 쪽은 방식을 정하지 못했다

## 상황
kind 의 PV 는 클러스터를 지우면 함께 사라진다 ([docs/todo.md](../todo.md) 33번). 전체 삭제 후 재설치 시험(todo 2번)과 원본 데이터를 올리기 전에, 클러스터 밖에 복사본이 있어야 한다.

## 선택지
1. **Windows 디스크의 폴더** (선택): WSL 의 `/mnt/c` 아래. 추가 설치와 비밀 키가 없고, `teardown/00-windows-wsl.ps1` 이 지우는 것은 WSL 배포판이라 `C:` 아래 폴더는 남는다.
2. 외장 디스크나 다른 PC: 경로가 정해지면 복사 스크립트만 더하면 된다. 지금은 경로가 없다.
3. 클라우드 객체 스토리지: S3 호환 버킷과 접근 키 관리와 비용이 생긴다.

## 결정
- 위치는 이 저장소와 나란히 있는 `backups/infra` (`$ROOT/../backups/infra`, `BACKUP_DIR` 로 바꿀 수 있다). 사용자 경로를 코드에 적지 않으려고 상대 경로로 계산한다.
- 저장소 밖이라 커밋되지 않는다. 상위 `backups/` 에는 `.gitignore`(`*`)를 두어 누가 `projects` 에서 `git init` 을 해도 올라가지 않게 한다.
- PostgreSQL: `pg_dump -Fc`(DB `app`). 받은 파일은 `pg_restore -l` 로 읽히는지 확인한 뒤에야 이름을 확정하고 sha256 을 남긴다. 검증은 실제 복원까지 한다 (시험 표를 넣고 백업, 임시 DB 에 복원, 값과 소유자 확인).
- 오래된 백업은 지우지 않는다 (보존 정책은 만들지 않았다).

## 알려진 한계 (모두 미시험)
- **같은 PC 의 디스크라 PC 고장이나 디스크 손상은 막지 못한다.** 중요한 데이터가 생기면 2번을 더한다.
- 역할은 받지 않는다 (`pg_dump` 는 역할을 담지 않고, `notebook_rw` 는 `10-2` 가 다시 만든다). 덤프에 그 역할의 권한이 들어 있으면 복원 전에 `10-2` 를 먼저 실행해야 하는지는 시험하지 못했다.
- 복원에 `--role=app` 이 필요하다고 판단했다: 슈퍼유저로 복원하면 소유자가 `postgres` 가 되기 때문이다. `verify/11-1` 이 소유자를 확인하지만 아직 실행하지 않았다.
- OpenSearch는 아래 '공식 문서가 말하는 것' 의 방식으로 정했고 **아직 실행하지 않았다**. `path.repo` 를 환경변수로 넣는 방식이 이 이미지에서 설정으로 적용되는지는 공식 문서에서 직접 확인하지 못했다 (Docker 문서가 `-e "discovery.type=single-node"` 처럼 점이 든 환경변수를 쓰는 것과 같은 방식이라는 추정). `verify/11-2` 의 첫 단계가 실제 적용을 확인한다.
- `11-2` 가 tar 로 저장소를 꺼내려면 OpenSearch 이미지에 `tar` 가 있어야 한다. 있는지 확인하지 못했고 스크립트가 없으면 멈춘다.
- 스냅샷은 `.` 으로 시작하는 시스템 인덱스와 global state 를 뺀다: Dashboards 의 저장된 객체(인덱스 패턴 등)와 보안 설정(게스트 계정, 역할)은 백업되지 않는다. 계정과 역할은 `09-3` 이 다시 만든다.
- 스냅샷 저장소는 `emptyDir` 이라 파드가 다시 만들어지면 비워진다. 그 뒤 첫 스냅샷은 전체 복사이고, tar 는 매번 저장소 전체라 백업이 쌓이면 커진다.
- `09-1` 을 다시 실행하면 OpenSearch 가 재시작된다 (StatefulSet 이 바뀐다).

## 공식 문서가 말하는 것: OpenSearch (2026-11-16 확인)
출처: [Take and restore snapshots](https://docs.opensearch.org/latest/tuning-your-cluster/availability-and-recovery/snapshots/snapshot-restore/), Helm 차트 `values.yaml` (`main` 브랜치, 설치한 3.8.0 태그와 같은지는 확인하지 못했다).
- `fs` 저장소: `opensearch.yml` 의 `path.repo` 와 모든 노드에 같은 경로의 마운트가 필요하다. 저장소는 `PUT /_snapshot/<이름>` 의 `{"type":"fs","settings":{"location":...}}` 로 등록한다.
- Security 플러그인이 있으면 `manage_snapshots` 가 필요하고, global state 와 `.opendistro_security` 가 든 스냅샷은 복원할 수 없다. 보안 인덱스는 스냅샷에서 빼라고 권한다.
- 복원 대상은 같은 버전이거나 새 버전이어야 한다 (이전 버전으로의 복원은 지원되지 않는다).
- Helm 차트의 `config` 는 `opensearch.yml` 기본값(`cluster.name`, `network.host`)을 통째로 바꾸게 되어 쓰지 않았다. `extraEnvs` 는 한 곳에서만 정의해야 해서 `09-1` 의 `--set` 에 `extraEnvs[1]` 로 더했다. `helm template` 로 렌더링해 환경변수와 볼륨이 파드 스펙에 들어가는 것을 확인했다 (클러스터에 적용하지는 않았다).
- Notebook 안의 데이터(PVC)는 범위 밖이다.
