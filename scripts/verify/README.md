# verify 스크립트

설치 스크립트(`scripts/NN-*.sh`)가 끝난 뒤, **"설치됨"이 아니라 "동작함"** 을 확인한다. 같은 번호의 설치 스크립트와 짝을 이룬다.
성공하면 마지막 줄에 `==> OK: ...` 가 찍히고 종료 코드가 0이다. 실패하면 `오류: ...` 를 찍고 0이 아닌 코드로 끝난다.

| 스크립트 | 실행 위치 | 확인하는 것 | 선행 |
|---|---|---|---|
| `00-windows.ps1` | Windows PowerShell (관리자 불필요) | 이 PC 가 WSL2 + GPU 서버 조건을 갖췄는가 | 없음 |
| `03-docker.sh` | WSL | Docker 가 컨테이너를 실행하는가 | `03-docker.sh` |
| `04-gpu.sh` | WSL | **1차 관문**: Docker 컨테이너에서 GPU 가 보이는가 | `04-nvidia-toolkit.sh` |
| `05-kind.sh` | WSL | **2차 관문**: kind 노드 안의 파드가 GPU 를 잡는가 | `05-kind.sh` |

아래 출력은 모두 이 저장소의 실제 환경(Windows 11 Home, WSL2 Ubuntu 24.04, RTX 5080 Laptop)에서 2026-10-23 에 실행한 결과다.

## 00-windows.ps1

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify\00-windows.ps1
```

```text
== OS         : Microsoft Windows 11 Home build 26200  (mirrored 네트워킹은 Windows 11 22H2 = 22621 이상)
== CPU        : Intel(R) Core(TM) Ultra 9 275HX / 24 코어 24 스레드
== RAM        : 31.4 GB
== 가상화     : 펌웨어 켜짐=False  Hypervisor 실행 중=True
== 디스크     : C: 여유 818 GB
== GPU        : Intel(R) Graphics / NVIDIA GeForce RTX 5080 Laptop GPU
== NVIDIA 드라이버:
NVIDIA GeForce RTX 5080 Laptop GPU, 592.27, 16303 MiB
== WSL:
(WSL 버전 정보와 배포판 목록)
```

- 이 스크립트는 값을 나열할 뿐 합격/불합격을 판정하지 않는다. 사람이 읽고 판단한다.
- "펌웨어 켜짐=False" 는 Hypervisor 가 이미 실행 중(`True`)이면 그렇게 보이는 경우가 있다. `Hypervisor 실행 중=True` 면 가상화는 켜진 것으로 본다.
- WSL 이 없으면 마지막 줄이 `WSL 미설치 -> scripts\00-windows-wsl.ps1 실행` 으로 끝난다.

## 03-docker.sh

```bash
bash scripts/verify/03-docker.sh
```

```text
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
...
Status: Downloaded newer image for hello-world:latest
==> OK: docker Docker version 29.8.2, build 7fc2dff
```

- 처음 실행할 때만 `hello-world` 이미지를 받는 로그가 나온다. 두 번째부터는 `==> OK` 한 줄만 찍힌다.
- `permission denied ... docker.sock` 이면 터미널을 새로 열어서 docker 그룹을 적용한다 (`03-docker.sh` 안내 참고).

## 04-gpu.sh (1차 관문)

```bash
bash scripts/verify/04-gpu.sh
```

```text
| NVIDIA-SMI 590.70                 Driver Version: 592.27         CUDA Version: 13.1     |
...
|   0  NVIDIA GeForce RTX 5080 ...    On  |   00000000:02:00.0 Off |                  N/A |
| N/A   52C    P4             27W /   79W |       0MiB /  16303MiB |      0%      Default |
...
|  No running processes found                                                             |
==> OK: 컨테이너에서 GPU 확인
```

- `nvidia-smi` 표 안에 GPU 이름과 메모리(16303MiB)가 보이면 된다. `Driver Version` 은 Windows 드라이버 값이다.
- `NVIDIA-SMI 590.70` 과 `Driver Version: 592.27` 이 서로 다르게 찍히지만, 이 환경에서는 GPU 가 정상 동작했다. WSL 의 nvidia-smi 도구 버전과 Windows 드라이버 버전이 따로 표시되는 것으로 보이나 원인은 확인하지 못했다.
- `could not select device driver "" with capabilities: [[gpu]]` 이면 toolkit 설정 문제다. `04-nvidia-toolkit.sh` 를 다시 실행한다.
- 컨테이너 이미지는 `versions.env` 의 `CUDA_TEST_IMAGE` 다. Blackwell 은 CUDA 12.8 이상 이미지가 필요하다.

## 05-kind.sh (2차 관문)

```bash
bash scripts/verify/05-kind.sh
```

```text
node/mlops-control-plane condition met
GPU 0: NVIDIA GeForce RTX 5080 Laptop GPU (UUID: GPU-c08fb173-ade5-64da-ffc8-986a6c854106)
==> 노드가 광고하는 GPU: 1
pod/gpu-smoke created
pod/gpu-smoke condition met
GPU 0: NVIDIA GeForce RTX 5080 Laptop GPU (UUID: GPU-c08fb173-ade5-64da-ffc8-986a6c854106)
pod "gpu-smoke" deleted from default namespace
==> OK: kind 노드 안의 파드에서 GPU 확인
```

네 단계를 순서대로 확인하고, 각 단계의 출력은 다음과 같다.

| 출력 | 의미 |
|---|---|
| `node/... condition met` | 노드가 Ready |
| 첫 번째 `GPU 0: ...` | **노드 컨테이너** 안에서 GPU 가 보임 |
| `노드가 광고하는 GPU: 1` | device plugin 이 노드에 `nvidia.com/gpu` 를 등록함 |
| 두 번째 `GPU 0: ...` | **파드** 안에서 GPU 가 보임 (`gpu-smoke` 의 로그) |

### 실패 예: 노드가 GPU 를 광고하지 않음

```text
node/mlops-control-plane condition met
GPU 0: NVIDIA GeForce RTX 5080 Laptop GPU (UUID: ...)
오류: 노드가 nvidia.com/gpu 를 광고하지 않습니다 (device plugin 로그 확인).
```

노드 컨테이너에서는 GPU 가 보이는데 광고가 안 되는 상태다. device plugin 로그를 본다.

```bash
export KUBECONFIG=$HOME/.kube/kind-mlops.yaml
kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds
kubectl -n kube-system logs -l name=nvidia-device-plugin-ds --tail=10
```

`Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND` 가 보이면 노드 안의 containerd 가 nvidia 런타임으로 설정되지 않은 것이다. `05-kind.sh` 의 노드 후처리 단계를 확인한다 ([troubleshooting.md](../../docs/troubleshooting.md) 8번).
`Detected platform: wsl` 과 `Registered device plugin for 'nvidia.com/gpu'` 가 보이면 정상이다.
