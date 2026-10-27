# 0006. NVIDIA GPU: Windows 드라이버 + Container Toolkit 1.20.1

- 상태: 채택, kind 안의 GPU 검증 완료 (2026-10-23)

## 상황
RTX 5080 Laptop (Blackwell, 16GB) 을 WSL2 의 컨테이너와 Kubeflow 에서 쓴다.

## 결정
- WSL 안에는 NVIDIA 드라이버를 설치하지 않는다. Windows 드라이버가 `/usr/lib/wsl` 로 공유된다. 현재 Windows 드라이버: 592.27.
- NVIDIA Container Toolkit **1.20.1** (이 버전에 WSL2 CDI 수정 포함), apt hold.
- 검증 이미지: `nvidia/cuda:12.8.1-base-ubuntu24.04`. Blackwell 은 CUDA 12.8 이상이 필요하다고 알려져 있다(검증 못 함).

## kind 에서 GPU 를 쓰는 방법 (Codex 조사, 2026-10-23)
`/dev/dxg`, `/usr/lib/wsl` 을 일반 `extraMounts` 로 bind mount 하지 않는다. bind mount 는 Docker 장치 할당이 아니라서 device cgroup 권한이 없을 수 있고, 하드코딩한 경로는 툴킷이 만드는 링크와 드라이버 스토어 파일을 놓친다. NVIDIA nvkind 의 **마커 마운트**를 쓴다.
1. 호스트: `nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled` 와 `nvidia-ctk config --in-place --set accept-nvidia-visible-devices-as-volume-mounts=true` (`04-nvidia-toolkit.sh`). nvkind README 에서 같은 명령을 확인했다.
2. 노드: `extraMounts` 에 `/dev/null` -> `/var/run/nvidia-container-devices/all` 하나만 (`k8s/kind-config.yaml`).
3. **노드 후처리 (Codex 레시피에 없던 단계, 실행으로 발견)**: 노드 컨테이너 안에 toolkit 을 설치하고 `nvidia-ctk runtime configure --runtime=containerd --config-source=file --set-as-default --cdi.enabled` 후 containerd 를 재시작한다. 호스트 Docker 의 nvidia 런타임은 노드 컨테이너까지만 GPU 를 넣고, 파드까지는 노드의 containerd 가 넣어야 하기 때문이다 (NVIDIA nvkind `pkg/nvkind/node.go` 와 같은 처리). 이 단계가 없으면 device plugin 이 `ERROR_LIBRARY_NOT_FOUND` 로 죽는다 ([troubleshooting.md](../troubleshooting.md) 7번).
4. 클러스터: NVIDIA k8s-device-plugin v0.20.1 (2026-09-22). GPU Operator 는 쓰지 않는다: WSL2 + kind 가 검증 플랫폼 목록에 없고 필요하지 않다.

**평가**: 동작한다 (아래 검증). 다만 우회 방식이고 사슬이 길다: Windows 드라이버, WSL, Docker, 노드 컨테이너, 노드의 containerd, device plugin. 업그레이드(드라이버, Docker, toolkit, kind)한 뒤에는 `verify/04-gpu.sh`, `verify/05-*` 를 다시 돌린다. 클러스터를 지우고 만들 때마다 노드 안 toolkit 설치가 반복된다.

## 검증 상태
- 1차 관문 **통과** (2026-10-23): `scripts/verify/04-gpu.sh` — Docker 컨테이너에서 RTX 5080, 드라이버 592.27.
- 2차 관문 **통과** (2026-10-23): `scripts/verify/05-3-device-plugin.sh` — 4노드 클러스터를 지우고 `05-1`~`05-3` 으로 처음부터 만든 뒤, GPU 노드 컨테이너, 노드의 `allocatable nvidia.com/gpu: 1`, `nvidia.com/gpu: 1` 을 요청한 파드 모두에서 RTX 5080 확인. 출력은 [scripts/verify/README.md](../../scripts/verify/README.md).
- Blackwell 전용 문제는 만나지 않았다. 단, 테스트 이미지는 `nvidia-smi -L` 만 실행한다. 실제 CUDA 연산(PyTorch 등)은 검증하지 않았다.

## 실패 시
ADR 0002 의 k3s 대안으로 전환한다.

## 출처 (확인 2026-10-23)
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/release-notes.html (1.20.1: WSL2 수정)
- https://docs.nvidia.com/cuda/wsl-user-guide/index.html
