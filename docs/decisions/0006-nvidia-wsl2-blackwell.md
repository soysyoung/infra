# 0006. NVIDIA GPU: Windows 드라이버 + Container Toolkit 1.20.1

- 상태: 채택, **kind 안의 GPU 는 미검증** (2026-10-23)

## 상황
RTX 5080 Laptop (Blackwell, 16GB) 을 WSL2 의 컨테이너와 Kubeflow 에서 쓴다.

## 결정
- WSL 안에는 NVIDIA 드라이버를 설치하지 않는다. Windows 드라이버가 `/usr/lib/wsl` 로 공유된다. 현재 Windows 드라이버: 592.27.
- NVIDIA Container Toolkit **1.20.1** (이 버전에 WSL2 CDI 수정 포함), apt hold.
- 검증 이미지: `nvidia/cuda:12.8.1-base-ubuntu24.04`. Blackwell 은 CUDA 12.8 이상이 필요하다고 알려져 있다(검증 못 함).

## 검증 상태
- 완료: 없음 (04 는 아직 실행 전).
- 1차 관문: `scripts/verify/04-gpu.sh` (Docker 컨테이너에서 nvidia-smi).
- 2차 관문(미정): kind 노드 안의 파드가 GPU 를 잡는지. 필요한 설정은 조사 중이다: `nvidia-ctk runtime configure --set-as-default`, `/dev/dxg` 와 `/usr/lib/wsl` 마운트, device plugin 또는 CDI. Codex 조사 요청은 Node.js 미설치로 실행되지 않았다.

## 실패 시
ADR 0002 의 k3s 대안으로 전환한다.

## 출처 (확인 2026-10-23)
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/release-notes.html (1.20.1: WSL2 수정)
- https://docs.nvidia.com/cuda/wsl-user-guide/index.html
