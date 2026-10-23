# 설치 스크립트

노트북(Windows 11 + WSL2 + RTX 5080)에 Tailscale, Docker, kind, Kubeflow 를 설치한다. 모든 명령은 **저장소 루트**(`infra`)에서 실행한다.

## 사전 요구

- Windows 11 22H2 이상 (build 22621+), 관리자 권한
- NVIDIA GPU 와 **Windows 쪽** NVIDIA 드라이버 (WSL 안에는 드라이버를 설치하지 않는다). 검증한 환경: RTX 5080 Laptop, 드라이버 592.27
- RAM 32GB 권장 (WSL 에 24GB 할당, Kubeflow 는 16GB 이상 권장), 디스크 여유 100GB 이상
- Tailscale 계정 (원격 접속용)
- 이 PC 가 조건을 갖췄는지는 `scripts\verify\00-windows.ps1` 로 확인한다

## 설정 파일

| 파일 | 내용 |
|---|---|
| [versions.env](../versions.env) | 모든 버전의 단일 출처 (kind, 노드 이미지, Docker, NVIDIA toolkit, Kubeflow, kustomize ...). 스크립트가 읽는다 |
| [cluster.env](../cluster.env) | 클러스터 토폴로지 (`CPU_WORKERS`, inotify 한도). 바꾸면 클러스터를 다시 만든다 |
| [windows/wslconfig.example](../windows/wslconfig.example) | `.wslconfig` 예시 (메모리 24GB, mirrored 네트워킹). `00` 이 복사한다 |

## 실행 순서

Windows 관리자 PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\00-windows-wsl.ps1   # 재부팅 안내가 나오면 재부팅 후 다시 실행
```

WSL Ubuntu 24.04 안에서:

```bash
bash scripts/01-wsl-systemd.sh        # 끝나면 PowerShell 에서 wsl --shutdown
bash scripts/02-tailscale.sh          # 로그인 URL 이 나오면 브라우저로 인증
bash scripts/03-docker.sh             # DOCKER_VERSION 이 비어 있으면 목록을 보여주고 멈춘다
bash scripts/04-nvidia-toolkit.sh
bash scripts/verify/04-gpu.sh         # GPU 1차 관문 (Docker 컨테이너)
bash scripts/05-1-kind-cluster.sh     # kind 4노드 (control-plane 1, GPU 1, CPU 2)
bash scripts/05-2-gpu-node.sh         # GPU 노드 컨테이너에 toolkit, containerd 설정
bash scripts/05-3-device-plugin.sh    # device plugin (GPU 노드에만)
bash scripts/verify/05-3-device-plugin.sh   # GPU 2차 관문 (GPU 노드의 파드)
bash scripts/06-kubeflow.sh           # Pipelines, Notebooks, KServe (첫 설치는 이미지를 많이 받아 오래 걸린다)
bash scripts/verify/06-kubeflow.sh
bash scripts/07-expose.sh            # (선택) tailnet 주소로 상시 접속: systemd 로 감싼 port-forward (방식 A)
bash scripts/verify/07-expose.sh
```

단계마다 짝이 되는 검증이 `scripts/verify/` 에 있다. 사용법과 실제 출력은 [verify/README.md](verify/README.md).

## Kubeflow 접속

```bash
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80   # http://localhost:8080
```

로그인은 `user@example.com` 이고, 비밀번호는 저장소 루트의 `.env` (git 제외) 의 `KUBEFLOW_PASSWORD` 다. 바꾼 뒤 `bash scripts/06-kubeflow.sh` 를 다시 실행하면 dex 에 반영된다. `.env` 가 없으면 공개된 기본값 `12341234` 이므로 바꾸기 전에는 외부에 노출하지 않는다 ([ADR 0005](../docs/decisions/0005-kubeflow-26.03.1.md)). 파드는 `kubectl get po -A` 로 본다 (Kubeflow 는 `default` 가 아닌 네임스페이스에 있다).

## 상시 접속 (tailnet)

`port-forward` 는 `127.0.0.1` 에만 열리고 터미널을 닫으면 끊긴다. 다른 기기에서 쓰려면 두 방식이 있고 차이는 [ADR 0009](../docs/decisions/0009-tailnet-exposure-a-vs-c.md) 에 정리했다.

- **A**: `bash scripts/07-expose.sh` -> `http://<tailnet 주소>:8080` (`tailscale ip -4`). 기존 클러스터에도 바로 된다.
- **C**: 클러스터를 만들 때 `kind-config.yaml` 이 포트를 열고 `06` 이 게이트웨이를 NodePort 로 바꾼다 -> `http://<tailnet 주소>:30080`. 별도 스크립트가 없고, 이미 만든 클러스터에는 지우고 `05-1` 부터 다시 해야 한다.

둘 다 `.env` 의 비밀번호를 바꾼 뒤에 연다. 아직 시험하지 못했다.

## 삭제

설치의 역순으로 지운다. 되돌릴 수 없으므로 먼저 `DRY_RUN=1` 로 확인한다. 사용법은 [teardown/README.md](teardown/README.md).
