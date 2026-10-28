# 0015. 프로필 네임스페이스의 ResourceQuota 는 06-4 한 곳이 맡는다

- 상태: 적용·검증 (2026-10-28). 남은 미검증은 아래 '확인한 것 / 미검증' 참고

## 상황
GPU 를 time-slicing 으로 4개 광고한다 ([ADR 0013](0013-gpu-time-slicing.md)). 프로필 네임스페이스별로 GPU 개수를 나눠야 한다. 지금은 두 번째 사용자(`kubeflow-guest-example-com`)만 `06-2` 가 할당량(파드 20, 스토리지 20Gi, GPU 0)을 걸고, 기본 사용자(`kubeflow-user-example-com`)는 할당량이 없다 (2026-10-28 읽기 전용 확인).

## 공식 문서·소스가 말하는 것
- 할당량은 `Profile.spec.resourceQuotaSpec` 으로 건다. 컨트롤러는 `Hard` 가 비어 있지 않으면 네임스페이스에 `kf-resource-quota` 를 만들거나 갱신하고, **비어 있으면 있는 `kf-resource-quota` 를 삭제한다**. 출처: [kubeflow/dashboard profile_controller.go](https://github.com/kubeflow/dashboard/blob/main/components/profile-controller/controllers/profile_controller.go) (2026-10-28 에 `main` 을 읽었다. 설치한 Kubeflow 26.03.1 태그의 소스와는 **대조하지 않았다**).
- 확장 리소스(`nvidia.com/gpu`)의 쿼터는 `requests.` 접두만 허용한다 (`requests.nvidia.com/gpu: 4`). 출처: [Kubernetes Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/#quota-for-extended-resources).
- 쿼터는 네임스페이스마다 따로 계산한다. 프로필 합계가 광고 개수를 넘는 것을 막는 장치는 없다 (문서에 그런 기능이 없다는 뜻이고, 이 클러스터에서 넘겨 시험하지는 않았다).

## 결정
- **담당은 `06-4-quotas.sh` 하나.** 두 프로필의 값을 모두 여기서 건다. `06-2` 는 Profile 을 만들 뿐 `resourceQuotaSpec` 을 쓰지 않는다. `06-2` 는 매번 `kubectl apply` 로 Profile 전체를 적용하므로 둘이 같은 필드를 가지면 `06-2` 를 다시 실행할 때 덮어쓴다 (이 이유로 한쪽만 갖는다).
- **순서는 `06` -> `06-2` -> `06-4`.** `06-2` 의 apply 는 이전 버전이 넣은 `resourceQuotaSpec` 을 한 번 지울 수 있으므로(`last-applied` 에 있던 필드) 06-4 를 이어서 실행한다. `06` 이 끝에서 둘을 차례로 부른다. `06` 을 다시 실행하면 기본 사용자 Profile 의 할당량이 어떻게 되는지는 시험하지 않았으므로 같은 이유로 `06-4` 를 마지막에 둔다.
- **값은 `quotas.env`.** `cluster.env` 는 "바꾸면 클러스터 재생성" 이라는 뜻이라 넣지 않았다. 비우면 그 항목은 제한하지 않는다. 06-4 는 세 키(`pods`, `requests.storage`, `requests.nvidia.com/gpu`)를 항상 명시한 merge patch 를 보내고, 비운 키는 `null` 로 지워 Profile 에 남지 않게 한다.
- **GPU 배분(제안, 사용자가 바꿀 수 있음):** 기본 사용자 3, 두 번째 사용자 0, 프로필 밖 예약 1 = 합계 4. 예약 1개는 OpenSearch GPU 인덱스 빌드 실험을 위해 비워 둔 것이다(todo 26번. 그 실험은 이 ADR 의 범위가 아니다). 합계가 `GPU_REPLICAS` 를 넘거나 GPU 를 제한하지 않는 프로필이 있으면 06-4 와 verify 가 경고한다 (중단하지 않는다).
- **기본 사용자의 `pods`, 스토리지는 제한하지 않는다.** 근거 있는 값이 없고, 파이프라인 실행이 파드를 많이 만들며 KFP 시스템 파드가 거부될 위험이 있어(todo 5번) **시험 전이라 뺐다** (미검증). 제한이 필요하면 `quotas.env` 에 적는다.
- 기본 사용자 GPU 3 의 단점: GPU Notebook 을 동시에 4개 띄울 수 없다. 필요하면 `quotas.env` 의 값을 4 로 바꾸고 06-4 를 다시 실행한다 (예약 1 이 깨져 합계 경고가 나온다).
- **CPU, 메모리 쿼터는 넣지 않는다.** KFP 시스템 파드가 requests 없이 거부될 수 있다 (todo 5번). 시험 후 추가한다.

## 한계 (사용자가 알아야 하는 것)
- **GPU 쿼터는 개수 배분이지 메모리 보호가 아니다.** 4개는 모두 같은 GPU 1장(VRAM 16303MiB)이고 VRAM 은 나뉘지 않는다. 쿼터 안에서도 한 파드가 VRAM 을 다 쓰면 다른 파드가 OOM 이 난다. 상한은 워크로드 코드에서 건다 (ADR 0013, todo 23번).
- `kubectl delete`/`apply` 로 `kf-resource-quota` 를 직접 고치면 컨트롤러가 되돌린다.
- `teardown/06-4` 를 실행하면 두 번째 사용자의 GPU 0 제한도 풀린다. 클러스터 삭제 시에는 필요 없어서 `teardown/all.sh` 에 넣지 않았다.
- 용량 값은 정규형(`1Gi`, `1024Mi` 아님)으로 적어야 verify 의 문자열 비교가 맞는다.

## 확인한 것 / 미검증
- 확인 (2026-10-28, 읽기 전용): Profile 두 개와 현재 쿼터(guest `pods 20 / gpu 0 / storage 20Gi`, 기본 사용자 없음), `kf-resource-quota` 의 소유자가 Profile. 새 patch 두 개는 `--dry-run=server` 로 CRD 스키마를 통과했고 결과 `hard` 가 기대와 같았다 (저장은 하지 않았다). 합계 경고와 형식 오류는 스크립트 함수를 단독 실행해 확인했다.
- 첫 적용 (2026-10-28, 사용자가 실행한 출력): `06-4` 가 기본 사용자 Profile 을 `patched`(변경), guest 를 `patched (no change)` 로 처리했다. 이어 `verify/06-4` 가 `==> OK`. 기본 사용자 `kf-resource-quota` 가 `requests.nvidia.com/gpu: 1/3`, 생성 후 11초로 나타났다: 컨트롤러가 Profile 변경을 몇 초 안에 반영해 쿼터 객체를 **만든다**. guest 는 `pods 0/20, requests.nvidia.com/gpu 0/0, requests.storage 0/20Gi` (객체 24시간 전, 바뀌지 않음). guest 의 `no change` 는 06-2 가 이미 같은 값을 넣어 둔 Profile 이기 때문이고, 06-2 를 쿼터 없이 다시 실행한 적은 없다.
- 같은 날 17분 뒤 재실행: 두 Profile 모두 `patched (no change)`, `verify/06-4` `==> OK`, 기본 사용자 쿼터 객체 생성 17분 전 (첫 적용과 이어지는 값). 멱등이다.
- 시험 결과 `verify/06-4-quotas.sh roundtrip` (2026-10-28, 사용자가 실행한 출력, 전체 `==> OK (roundtrip)`):
  - **A 갱신·비운 키 통과.** 기본 사용자 쿼터를 GPU 3->2, pods 50, 스토리지 30Gi 로 바꾸자 같은 객체(나이 33분 그대로)가 갱신됐고(`pods 1/50, gpu 1/2, storage 5Gi/30Gi`), pods 를 다시 비우자 그 키가 사라졌다(`gpu 1/2, storage 5Gi/30Gi`). 제한을 푸는 방법이 동작한다.
  - **B 거부 통과.** GPU 0 인 guest 네임스페이스에 `nvidia.com/gpu: 1` 파드를 `--dry-run=server` 로 보내자 응답에 `exceeded quota` 가 있었다: 이 클러스터에서 쿼터 어드미션은 서버 dry-run 에서도 평가된다. 거부 문구 전체는 스크립트가 출력하지 않아 기록하지 않았다. 기본 사용자 네임스페이스의 한도 초과 거부는 시험하지 않았다.
  - **C 순서 통과.** 새 `06-2` 가 guest Profile 을 `configured` 하자 `kf-resource-quota` 가 지워졌다(`- - -`): 예상대로 apply 가 옛 `resourceQuotaSpec` 을 지운다. `06-4` 를 이어서 실행하자 객체가 다시 만들어져 `pods 0/20, gpu 0/0, storage 0/20Gi` 로 돌아왔다(나이 1초). 지워진 동안 guest 는 제한이 없었다. Dex 재시작은 `successfully rolled out` 로 끝났다.
  - 마지막 복원도 `quotas.env` 값으로 돌아와 `verify` 통과(기본 사용자 `gpu 1/3`).
- 두 번째 `roundtrip` (2026-10-28, 사용자가 실행한 출력, 전체 `==> OK (roundtrip)`): A 는 같은 결과로 다시 통과했다.
  - **E 통과.** 기본 사용자 네임스페이스에 GPU 4개(한도 3 초과) 파드를 서버 dry-run 으로 보내자 `exceeded quota` 로 거부됐다.
  - **B 통과.** guest 의 GPU 1개 요청이 같은 방식으로 거부됐다.
  - **C, D 통과.** 이번에는 `06-2` 가 Profile 을 `unchanged` 로 처리했고 `kf-resource-quota` 는 지워지지 않았다(`20 20Gi 0` 유지, 객체 나이가 끊기지 않고 이어짐). 한 번 더 실행한 D 도 같다. 첫 새 `06-2` 에서만 옛 `resourceQuotaSpec` 이 한 번 지워지고(위 첫 `roundtrip`), 그 뒤의 `06-2` 는 쿼터를 건드리지 않는다는 추정이 연속 2회 실행으로 확인됐다.
- **여전히 미검증:** `06` 전체 재실행 경로(todo 3번). `06` 은 `kubectl apply --server-side --force-conflicts` 로 적용하고 06-4 의 patch 는 다른 관리자(`kubectl-patch`)가 소유한 필드라 지워지지 않을 가능성이 높다고 **추정**하지만 시험하지 않았다. `06` 이 끝에서 06-2 다음에 06-4 를 부르므로 지워져도 되돌아온다. 쿼터 거부 문구 전체도 기록하지 않았다.
