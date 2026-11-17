# 0013. GPU 1장을 time-slicing 으로 여러 개로 광고

- 상태: 적용·부분 검증 (2026-10-28). 아래 '적용 결과' 참고, 동시 실행은 미시험

## 상황
워크로드(추천 서비스 등)가 GPU 를 쓰는 파드를 동시에 여러 개 올려야 한다. 이 PC 의 GPU 는 1장이고 지금은 `nvidia.com/gpu: 1` 만 광고해서 GPU 파드 하나가 GPU 를 독점한다. device plugin(v0.20.1)에는 time-slicing 설정이 없었다 (static 매니페스트의 `env: []`, ConfigMap 없음, 저장소에 time-slicing 언급 없음).

## 공식 문서가 말하는 것
출처: [NVIDIA/k8s-device-plugin v0.20.1 README](https://github.com/NVIDIA/k8s-device-plugin/blob/v0.20.1/README.md) 'Shared Access to GPUs' (2026-10-28 에 가져옴).
- 설정 파일의 `sharing.timeSlicing.resources[].replicas` 로 GPU 하나를 N 개로 광고한다. 설정 파일은 `--config-file` 또는 `CONFIG_FILE` 환경변수로 가리킨다.
- **"nothing special is done to isolate workloads"**: 같은 GPU 를 받은 워크로드는 GPU 메모리를 모두 볼 수 있고 같은 장애 영역에 있다 (하나가 죽으면 모두 죽는다).
- 개수 2 이상을 요청해도 비례한 연산 시간을 보장받지 않는다. `failRequestsGreaterThanOne: true` 를 권장하고, 기본값은 하위 호환 때문에 false.
- time-slicing 과 MPS 는 동시에 못 쓴다. MPS 는 메모리를 균등 분할해 강제하지만 문서가 v0.15.0 기준 실험적이라 한다.
- 문서의 `rename by default` 를 켜면 자원 이름이 `nvidia.com/gpu.shared` 로 바뀐다.

## 기준선 (적용 전, 2026-10-28)
- 호스트(WSL)와 GPU Notebook 안의 `nvidia-smi` 가 같은 GPU 를 보여 준다: RTX 5080, 드라이버 592.27, CUDA 13.1, VRAM 16303MiB, 유휴 상태에서 사용 0MiB, 0%.
- 노드 `mlops-worker` 의 `nvidia.com/gpu` 광고는 1. Notebook 파드 하나가 이것을 점유한다.
- WSL 에서는 `nvidia-smi` 의 Processes 목록이 비어 있는 경우가 많다고 알려져 있다 (이 PC 에서 연산 중에는 미확인). 점유 비교는 Memory-Usage 숫자로 한다.
- 적용 뒤에는 광고가 4 가 되어야 하고, 같은 명령의 VRAM 총량(16303MiB)은 그대로여야 한다 (나뉘지 않음).

## 결정
- `nvidia.com/gpu` 이름은 그대로 두고(`renameByDefault` 끄기) **4개**로 광고한다 (`cluster.env` 의 `GPU_REPLICAS`). 이름을 바꾸면 기존 PodDefault([k8s/gpu-poddefault.yaml](../../k8s/gpu-poddefault.yaml))와 Notebook 의 GPU 요청을 모두 고쳐야 한다.
- `failRequestsGreaterThanOne: true`: GPU 2개 요청이 "더 빠른 GPU" 로 오해되지 않게 한다.
- 4 인 이유(제 판단, 문서 밖): 동시 사용처가 Notebook 1 ~ 2, 학습 또는 파이프라인 1, 추론 1 정도라서 넉넉히 잡은 값이다. VRAM 은 나뉘지 않으므로 개수를 늘려도 쓸 수 있는 메모리는 늘지 않는다. 부족하면 `GPU_REPLICAS` 만 바꿔 05-3 을 다시 실행한다 (클러스터 재생성 불필요).
- 구현: ConfigMap(`k8s/device-plugin-config.yaml`)을 만들고 DaemonSet 에 `CONFIG_FILE` 과 마운트를 strategic merge 로 더한다. static 매니페스트는 그대로 쓴다 (helm 으로 바꾸는 것은 이번 범위 밖).

## 한계 (사용자가 알아야 하는 것)
- **VRAM 은 격리되지 않는다.** 한 파드가 GPU 메모리를 다 쓰면 다른 파드가 OOM 이 난다. 4개로 광고돼도 메모리는 노트북 GPU 하나다. 워크로드 쪽에서 프레임워크 메모리 상한(예: PyTorch `set_per_process_memory_fraction`)을 걸어야 한다.
- 한 파드의 GPU 오류가 같은 GPU 의 다른 파드를 함께 죽일 수 있다.
- 연산은 시간 분할이라 동시에 돌리면 각자 느려진다.
- 공유용 계정(`guest`)의 GPU 할당량은 0 으로 유지한다 (todo 5번).

## 적용 결과 (2026-10-28, 사용자가 실행한 출력)
- `05-3-device-plugin.sh`: ConfigMap 생성, DaemonSet 패치와 재시작, `successfully rolled out`. 클러스터를 다시 만들지 않고 기존 클러스터에 적용됐다.
- `verify/05-3-device-plugin.sh`: `mlops-worker` 가 광고하는 GPU 4 (기대 4), 스모크 파드가 `NVIDIA GeForce RTX 5080 Laptop GPU` 를 보고 `OK`.
- 적용 뒤 Notebook `test-gpu-01` 을 다시 켰더니 `mlops-worker` 에서 2/2 Running, limits `nvidia.com/gpu: 1`, 노드 광고 4, 컨테이너 안 `nvidia-smi` 가 적용 전과 같은 GPU (VRAM 16303MiB, 사용 0MiB)를 보여 줬다.
- 적용 전 Notebook 은 중지해 둔 상태였다. 실행 중인 GPU 파드가 있을 때 광고가 1 에서 4 로 바뀌면 어떻게 되는지는 시험하지 않았다.

## 미검증
- GPU 파드 여러 개의 동시 실행, 그때의 VRAM 공유와 연산 속도.
- ConfigMap 만 바뀐 재실행(개수 변경)에서 `rollout restart` 로 설정이 반영되는지 (첫 적용에서는 재시작이 정상 동작했다).
- 삭제: ConfigMap 은 `kube-system` 에 있고 클러스터와 함께 사라지므로 teardown 스크립트 변경은 없다.
