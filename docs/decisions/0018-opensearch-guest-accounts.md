# 0018. OpenSearch 게스트 계정 2개 (역할 분리)

- 상태: 적용 (2026-10-30). 사용자가 `09-3` 을 실행했고, 계정 생성은 읽기 전용 조회로 확인했다. 두 계정의 로그인은 사용자 보고다. `verify/09-3` 의 출력은 받지 못했다

## 상황
Notebook(퍼널로 공유될 수 있는 계정 포함)과 Dashboards 공유에 admin 비밀번호를 넘기면 그 사용자가 OpenSearch 전체 권한을 갖는다. 접근할 인덱스를 좁힌 계정이 필요하다.

## 확인한 것 (2026-10-30, 공식 문서)
출처: [Create or update user](https://docs.opensearch.org/latest/security/api/users/create-user/), [Create or update role](https://docs.opensearch.org/latest/security/api/roles/create-role/), [Create or update role mapping](https://docs.opensearch.org/latest/security/api/role-mappings/create-role-mapping/), [Patch role mappings](https://docs.opensearch.org/latest/security/api/role-mappings/patch-role-mappings/), [Default action groups](https://docs.opensearch.org/latest/security/access-control/default-action-groups/), [Defining users and roles](https://docs.opensearch.org/latest/security/access-control/users-roles/). 검색 결과 발췌와 페이지 질의로 읽었고 페이지 전문은 읽지 않았다.
- 사용자(`PUT /_plugins/_security/api/internalusers/<이름>`, `password` 평문 또는 `hash`), 역할(`PUT .../roles/<이름>`, `cluster_permissions`, `index_permissions` 의 `index_patterns`, `allowed_actions`), 역할 매핑(`PUT .../rolesmapping/<역할>`, `users` 등)은 모두 **만들거나 통째로 교체**한다.
- 기본 action group: `cluster_composite_ops` 는 bulk 를 포함하고 `cluster_composite_ops_ro` 는 읽기 전용(mget, msearch 등). 인덱스 쪽은 `read`(검색, 조회), `crud`(읽기+쓰기, 인덱스 삭제와 `_refresh`, forcemerge 는 포함하지 않는 것으로 읽었다), `indices_all`(`indices:*`).
- `kibana_user` 역할은 Dashboards 로그인과 사용(Dashboards 인덱스 쓰기 포함)을 허용하고, 데이터에 대한 읽기는 따로 줘야 한다.
- 역할과 매핑이 `reserved` 이면 REST API 로 바꿀 수 없다.

## 결정
- 계정 2개, 역할 2개 (설정은 `scripts/09-3-opensearch-guests.sh`):

| 계정 (기본 이름) | 역할 | 클러스터 권한 | 인덱스 권한 (패턴 `temp-*`) |
|---|---|---|---|
| guest-rw | guest_rw | cluster_composite_ops | indices_all |
| guest-ro | guest_ro + kibana_user | cluster_composite_ops_ro | read |

- 인덱스 패턴은 `temp-*` 이다 (사용자 지정). `*` 로 두면 `.kibana` 같은 시스템 인덱스까지 열려서 패턴이 꼭 필요하다. 스크립트의 `INDEX_PATTERN` 한 줄을 바꾸고 다시 실행하면 갱신된다. 워크로드의 인덱스 이름이 이 패턴에 맞아야 한다.
- rw 가 `crud` 가 아니라 `indices_all` 인 이유: Notebook 에서 인덱스를 지우고 다시 만들거나 `_refresh`, force merge 를 부르는 일이 흔한데 `crud` 는 이를 허용하지 않는 것으로 읽었다. 범위가 `temp-*` 로 고정이라 `indices_all` 도 다른 인덱스에는 영향이 없다 (이름이 임시 공간이다).
- `kibana_user` 매핑을 `PUT` 으로 덮어쓰면 기존 매핑이 지워질 수 있어서 쓰지 않는다. 데모 구성에서 이 역할이 백엔드 역할 `kibanauser` 에 매핑돼 있다고 알려져 있어서, guest-ro 에 그 백엔드 역할을 붙인다. **`09-3` 이 먼저 `GET` 으로 매핑에 `kibanauser` 가 있는지 확인하고 없으면 멈춘다** (이 가정은 문서로 확인하지 못했다).
- 계정 이름과 비밀번호는 `.env` 의 `OPENSEARCH_GUEST_RW_USER`, `_PASSWORD`, `OPENSEARCH_GUEST_RO_USER`, `_PASSWORD`. 없으면 `09-3` 이 만들고(비밀번호는 09-1 과 같은 방식의 무작위 값), 직접 정하려면 실행 전에 `.env` 에 적는다. 다시 실행하면 `.env` 값으로 맞춰진다.
- 비밀번호는 명령줄에 나오지 않게 표준입력(`--data-binary @-`, `curl -K -`)으로 넘긴다.
- Notebook 에는 guest-rw 의 이름과 비밀번호만 준다 (Secret 과 PodDefault 로 환경변수 주입, [ADR 0020](0020-notebook-opensearch-guest-env.md)). Dashboards 를 외부에 보일 때는 guest-ro 를 쓴다 ([ADR 0019](0019-dashboards-tailscale-serve-funnel.md)).

## 알려진 한계
- 계정은 보안 인덱스(OpenSearch 의 PVC)에 있다. `teardown/09-1` 이나 admin 비밀번호 재설정 뒤에는 사라지거나 덮어써지므로 `09-3` 을 다시 실행한다. 공식 문서는 `securityadmin` 으로 반영하면 REST 로 만든 사용자가 덮어써진다고 경고한다.
- `.env` 의 계정 이름을 바꾸고 다시 실행하면 옛 사용자는 남는다 (자동으로 지우지 않는다).
- guest-ro 는 `kibana_user` 때문에 Dashboards 인덱스(`.kibana*`)에는 쓸 수 있다 (저장된 검색, 시각화). 데이터 인덱스는 읽기만 된다.

## 미검증 (적용 전)
- `09-3` 이 실제로 끝까지 도는지. admin 이 보안 REST API 를 부를 수 있는지(데모 구성이 `restapi.roles_enabled` 를 설정한다고 알려져 있으나 확인하지 못했다). 거부되면 `PUT` 이 403 으로 실패하고 스크립트가 응답과 함께 멈춘다.
- `kibana_user` 가 백엔드 역할 `kibanauser` 에 매핑돼 있는지 (스크립트가 확인한다).
- guest-ro 가 브라우저에서 Dashboards 에 로그인되고 `temp-*` 만 보이는지. `verify/09-3` 은 이를 시험하지 않는다.
- `verify/09-3` 의 기대 응답 코드(예: 문서 생성 201, 거부 403)는 일반적인 동작에서 정한 값이고 이 클러스터에서 확인한 값이 아니다.
- 읽기 전용 계정으로 k-NN 검색(`knn` 쿼리)이 `read` 만으로 되는지 (`verify/09-3` 이 확인한다).

## 적용 결과 (2026-10-30)
- 직접 확인 (보안 REST API 를 admin 으로 `GET`, 비밀번호는 출력하지 않음): 사용자 `guest-ro`(백엔드 역할 `kibanauser`)와 `guest-rw`(백엔드 역할 없음), 역할 매핑 `guest_rw`, `guest_ro`(각각 해당 사용자 하나), 역할 `guest_ro` = 클러스터 `cluster_composite_ops_ro`, 인덱스 `temp-*` 에 `read`. `kibana_user` 매핑에는 백엔드 역할 `kibanauser` 가 있었다 (스크립트의 가정이 맞았다). 이 조회 전에는 사용자도 역할도 없었고 `.env` 에만 값이 있었다. 역할 `guest_rw` 본문은 조회하지 않았다.
- 사용자 보고: guest-rw, guest-ro 모두 로그인된다.
- 미해소: 로그인 뒤 무엇이 보이고 되는지. guest-rw 는 `kibana_user` 가 없으므로 로그인은 돼도 Dashboards 화면에서 오류가 나거나 제한될 수 있고, guest-ro 가 `temp-*` 만 보는지도 확인하지 못했다. `verify/09-3` 의 결과(허용·거부 코드)도 받지 못했다.
- 직접 정한 비밀번호(19자)가 보안 플러그인에 받아들여졌다 (사용자가 `.env` 에 먼저 적고 `09-3` 을 실행했다).
