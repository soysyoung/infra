# verify 스크립트

설치 스크립트(`scripts/NN-*.sh`)가 끝난 뒤, **"설치됨"이 아니라 "동작함"** 을 확인한다. 같은 이름의 설치 스크립트와 짝을 이룬다.
성공하면 마지막 줄에 `==> OK: ...` 가 찍히고 종료 코드가 0이다. 실패하면 `오류: ...` 를 찍고 0이 아닌 코드로 끝난다.

| 스크립트 | 실행 위치 | 확인하는 것 | 선행 |
|---|---|---|---|
| `00-windows.ps1` | Windows PowerShell (관리자 불필요) | 이 PC 가 WSL2 + GPU 서버 조건을 갖췄는가 | 없음 |
| `03-docker.sh` | WSL | Docker 가 컨테이너를 실행하는가 | `03-docker.sh` |
| `04-gpu.sh` | WSL | **1차 관문**: Docker 컨테이너에서 GPU 가 보이는가 | `04-nvidia-toolkit.sh` |
| `05-1-kind-cluster.sh` | WSL | 노드 4개 Ready, GPU 노드 라벨/taint, 일반 파드가 GPU 노드를 피함 | `05-1-kind-cluster.sh` |
| `05-2-gpu-node.sh` | WSL | GPU 노드 컨테이너에서 GPU 가 보이고 containerd 가 nvidia 런타임인가 | `05-2-gpu-node.sh` |
| `05-3-device-plugin.sh` | WSL | **2차 관문**: GPU 파드가 GPU 노드에서 GPU 를 잡는가 | `05-3-device-plugin.sh` |
| `06-kubeflow.sh` | WSL | 핵심 네임스페이스의 Deployment 가 Available 이고 로그인 흐름이 이어지는가 | `06-kubeflow.sh` |

아래 출력은 모두 이 저장소의 실제 환경(Windows 11 Home, WSL2 Ubuntu 24.04, RTX 5080 Laptop)에서 2026-10-23 에 실행한 결과다. 2026-10-26 에 `03`~`06` 을 같은 클러스터에서 다시 실행해 모두 `==> OK` 로 끝났고 출력 형식은 같았다 (`nvidia-smi` 의 온도/전력, 노드 AGE, 일반 파드가 배치된 노드 이름만 다르다).

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

## 05-1-kind-cluster.sh

```bash
bash scripts/verify/05-1-kind-cluster.sh
```

```text
node/mlops-control-plane condition met
node/mlops-worker condition met
node/mlops-worker2 condition met
node/mlops-worker3 condition met
NAME                  STATUS   ROLES           AGE   VERSION   GPU.PRESENT
mlops-control-plane   Ready    control-plane   44s   v1.36.4   
mlops-worker          Ready    <none>          33s   v1.36.4   true
mlops-worker2         Ready    <none>          33s   v1.36.4   
mlops-worker3         Ready    <none>          33s   v1.36.4   
pod/cpu-smoke created
pod/cpu-smoke condition met
pod "cpu-smoke" deleted from default namespace
==> OK: 노드 4 개 Ready, GPU 노드 mlops-worker (taint 적용), 일반 파드는 mlops-worker2 에 배치됨
```

- 표의 `GPU.PRESENT` 열에서 `true` 인 노드가 GPU 노드다. 정확히 한 개여야 한다.
- 마지막 줄의 "일반 파드는 ... 에 배치됨"이 GPU 노드가 아닌 CPU 워커여야 한다. GPU 노드면 taint 가 걸리지 않은 것이다. 어느 CPU 워커인지는 실행마다 다르다 (`mlops-worker2` 또는 `mlops-worker3`).
- `노드가 N 개입니다`: 기대값은 4 이다 (control-plane 1 + 워커 3).

## 05-2-gpu-node.sh

```bash
bash scripts/verify/05-2-gpu-node.sh
```

```text
GPU 0: NVIDIA GeForce RTX 5080 Laptop GPU (UUID: GPU-c08fb173-ade5-64da-ffc8-986a6c854106)
==> OK: mlops-worker 에서 GPU 확인, containerd nvidia 런타임 설정됨
```

- `GPU 0: ...` 는 **GPU 노드 컨테이너 안**에서 본 GPU 다 (아직 파드는 아니다).
- `containerd 가 nvidia 런타임으로 설정되지 않았습니다` 이면 `05-2-gpu-node.sh` 를 다시 실행한다.

## 05-3-device-plugin.sh (2차 관문)

```bash
bash scripts/verify/05-3-device-plugin.sh
```

```text
==> mlops-worker 가 광고하는 GPU: 1
pod/gpu-smoke created
pod/gpu-smoke condition met
GPU 0: NVIDIA GeForce RTX 5080 Laptop GPU (UUID: GPU-c08fb173-ade5-64da-ffc8-986a6c854106)
pod "gpu-smoke" deleted from default namespace
==> OK: GPU 파드가 mlops-worker 에서 GPU 를 잡음
```

| 출력 | 의미 |
|---|---|
| `노드가 광고하는 GPU: 1` | device plugin 이 노드에 `nvidia.com/gpu` 를 등록함 |
| `GPU 0: ...` | **파드 안**에서 GPU 가 보임 (`gpu-smoke` 의 로그) |
| 마지막 줄의 노드 이름 | GPU 파드가 GPU 노드에 배치됨 |

### 실패 예: 노드가 GPU 를 광고하지 않음

```text
오류: 노드가 nvidia.com/gpu 를 광고하지 않습니다 (device plugin 로그 확인).
```

노드 컨테이너에서는 GPU 가 보이는데(`05-2` 통과) 광고가 안 되는 상태다. device plugin 로그를 본다.

```bash
kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds
kubectl -n kube-system logs -l name=nvidia-device-plugin-ds --tail=10
```

`Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND` 가 보이면 GPU 노드의 containerd 가 nvidia 런타임으로 설정되지 않은 것이다 (`05-2-gpu-node.sh`, [troubleshooting.md](../../docs/troubleshooting.md) 8번).
`Detected platform: wsl` 과 `Registered device plugin for 'nvidia.com/gpu'` 가 보이면 정상이다.
`device plugin 이 N 개 노드에 배치되었습니다`: 기대는 GPU 노드 1개다. `05-3-device-plugin.sh` 의 nodeSelector 패치를 확인한다.

## 06-kubeflow.sh

```bash
bash scripts/verify/06-kubeflow.sh
```

```text
deployment.apps/profiles-deployment condition met
deployment.apps/pvcviewer-controller-manager condition met
deployment.apps/seaweedfs condition met
...
==> /oauth2/start 의 리다이렉트: http://localhost:8080/dex/auth?client_id=kubeflow-oidc-authservice&...
==> OK: Kubeflow 구성요소가 Available 이고 로그인 흐름(oauth2-proxy -> Dex)이 동작함
```

7개 네임스페이스(`cert-manager`, `istio-system`, `auth`, `oauth2-proxy`, `knative-serving`, `kubeflow-system`, `kubeflow`)의 Deployment 가 Available 인지(Deployment 가 없는 네임스페이스는 건너뜀), `Running`/`Completed` 가 아닌 파드가 없는지, 로그인 흐름이 이어지는지를 순서대로 확인한다.

- `condition met` 줄은 Deployment 마다 한 줄씩이라 길다.
- 로그인 흐름은 `/oauth2/start` 가 Dex(`/dex/auth`)로 리다이렉트하는지로 본다.
- **로그인 전 `/` 는 `HTTP 403` 이 정상이다.** 응답 본문이 oauth2-proxy 의 "Sign In" 페이지이고 게이트웨이 로그에 `ext_authz_denied` 가 찍힌다. 처음에는 이 403 을 실패로 판정하는 검증을 썼다가 고쳤다 ([troubleshooting.md](../../docs/troubleshooting.md) 15번).
- `Running/Completed 가 아닌 파드가 있습니다` 이면 `kubectl get pods -A` 로 확인한다. `Init:Error` 면 [troubleshooting.md](../../docs/troubleshooting.md) 10번이다 (`06-kubeflow.sh` 를 다시 실행하면 정리된다).

## 07-1-port-forward.sh, 07-3-tailscale-serve.sh (07-2-nodeport.sh 는 쓰지 않음)

```bash
bash scripts/verify/07-1-port-forward.sh   # http://127.0.0.1:8080
bash scripts/verify/07-3-tailscale-serve.sh   # https://<기기>.<tailnet>.ts.net
```

각각 `/oauth2/start` 가 `/dex/auth` 로 리다이렉트하는지 확인한다. `07-1` 은 `kubeflow-port-forward` 서비스가 실행 중인지도 본다. `07-3` 은 리다이렉트가 **`https://` 를 유지하는지**도 본다 (`http://` 로 떨어지면 Secure 쿠키가 거부된다). `07-2-nodeport.sh` 의 검증(`verify/07-2-nodeport.sh`)은 시험 기록용이다. 결정 근거는 [ADR 0011](../../docs/decisions/0011-no-nodeport-https-via-tailscale-serve.md).

실제 출력 (2026-10-26, tailnet 이름은 가렸다):

```text
==> 127.0.0.1:8080: OK  (http://127.0.0.1:8080/dex/auth?client_id=kubeflow-oidc-authservice&...)
==> OK: port-forward 방식으로 Kubeflow 로그인 흐름(oauth2-proxy -> Dex)이 동작함

==> https://<기기>.<tailnet>.ts.net/oauth2/start 의 리다이렉트: https://<기기>.<tailnet>.ts.net/dex/auth?client_id=kubeflow-oidc-authservice&...
==> OK: https://<기기>.<tailnet>.ts.net 로 Kubeflow 로그인 흐름이 HTTPS 를 유지하며 동작함
```

`tailscale serve status`: `https://<기기>.<tailnet>.ts.net (tailnet only)` -> `/ proxy http://127.0.0.1:8080`.

이전 기록: 2026-10-26 까지는 `verify/07-expose.sh`(지금은 없음) 한 스크립트가 tailnet 주소의 HTTP 8080(port-forward)과 30080(NodePort)을 함께 확인했고, 그 출력은 아래 08 절에 있다 (당시 라벨은 '방식 A / 방식 C').

## 08-reboot.sh

```bash
bash scripts/verify/08-reboot.sh
```

재부팅하고 몇 분 기다린 뒤 실행한다. `docker`, `tailscaled` 서비스, 노드 컨테이너의 재시작 정책(`unless-stopped`), 노드 Ready, 파드 상태를 보고, **적용한 노출 방식만** 골라 접속을 확인한다 (`kubeflow-port-forward` 서비스가 있으면 `07-1`, 게이트웨이 Service 가 NodePort 면 `07-2`, 둘 다 아니면 실패). 근거는 [ADR 0010](../../docs/decisions/0010-reboot-recovery.md).

아래 출력에 찍힌 '방식 A / 방식 C' 는 당시 스크립트의 라벨이고, 지금은 'port-forward 방식 / NodePort 방식' 으로 찍힌다.

실제 출력 (2026-10-26, **재부팅 전** 상태. WSL 가동 시간이 2일 12시간이라 재부팅 시험이 아니다. 긴 리다이렉트 주소는 줄였다):

```text
==> docker: active
==> tailscaled: active
==> kubeflow-port-forward: active
==> WSL 가동 시간: up 2 days, 12 hours, 25 minutes
==> 노드 컨테이너 재시작 정책: unless-stopped
node/mlops-control-plane condition met
node/mlops-worker condition met
node/mlops-worker2 condition met
node/mlops-worker3 condition met
==> 방식 A (<tailnet IP>:8080): OK  (http://<tailnet IP>:8080/dex/auth?client_id=kubeflow-oidc-authservice&...)
==> 방식 C (<tailnet IP>:30080): 응답 없음 또는 로그인 흐름이 아님
==> OK: tailnet 주소로 Kubeflow 로그인 흐름(oauth2-proxy -> Dex)이 동작함
==> OK: 재부팅 후 서비스, 노드, Kubeflow 접속이 모두 돌아옴
```

NodePort 방식이 "응답 없음" 인 것은 정상이다 (현재 클러스터에 포트 매핑이 없다, [ADR 0009](../../docs/decisions/0009-tailnet-exposure-port-forward-vs-nodeport.md)). 마지막 줄의 "재부팅 후" 는 스크립트의 고정 문구라 이 출력이 재부팅을 증명하지 않는다. 재부팅 후 출력 (2026-10-26 10:32, '다시 시작' 재부팅 약 5분 뒤. WSL 가동 시간이 4분이다):

```text
### WSL 가동: up 4 minutes  / 지금 10:32:34
==> docker: active
==> tailscaled: active
==> kubeflow-port-forward: active
==> WSL 가동 시간: up 4 minutes
==> 노드 컨테이너 재시작 정책: unless-stopped
node/mlops-control-plane condition met
node/mlops-worker condition met
node/mlops-worker2 condition met
node/mlops-worker3 condition met
==> 방식 A (<tailnet IP>:8080): OK  (http://<tailnet IP>:8080/dex/auth?client_id=kubeflow-oidc-authservice&...)
==> 방식 C (<tailnet IP>:30080): 응답 없음 또는 로그인 흐름이 아님
==> OK: tailnet 주소로 Kubeflow 로그인 흐름(oauth2-proxy -> Dex)이 동작함
```

Ready 시각(UTC): oauth2-proxy 01:28:04, istio 게이트웨이와 dex 01:28:43. 노드 컨테이너 StartedAt 01:27:52 (KST 10:27:52). 타임라인과 한계는 [ADR 0010](../../docs/decisions/0010-reboot-recovery.md).
