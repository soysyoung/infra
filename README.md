# infra

노트북(Windows 11 + WSL2 + RTX 5080)을 원격 MLOps 서버로 만드는 프로젝트. Tailscale, Docker, kind, Kubeflow 를 셸 스크립트로 설치하고, 이후 Terraform 으로 코드화한다.

- 구성도: [docs/architecture.md](docs/architecture.md)
- 버전과 선택 근거: [docs/versions.md](docs/versions.md), [docs/decisions/](docs/decisions/)
- 막힌 곳과 해결: [docs/troubleshooting.md](docs/troubleshooting.md)
- 검증 스크립트 사용법과 실제 출력: [scripts/verify/README.md](scripts/verify/README.md)
- 커밋 규칙: [docs/commit-convention.md](docs/commit-convention.md)
- 생성형 AI 사용 기록: [docs/ai-usage.md](docs/ai-usage.md)

## 실행 순서

Windows 관리자 PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\00-windows-wsl.ps1   # 재부팅 안내가 나오면 재부팅 후 다시 실행
```

WSL Ubuntu 24.04 안에서 (`versions.env` 의 버전을 따른다):

```bash
bash scripts/01-wsl-systemd.sh   # 끝나면 PowerShell 에서 wsl --shutdown
bash scripts/02-tailscale.sh
bash scripts/03-docker.sh        # DOCKER_VERSION 이 비어 있으면 목록을 보여주고 멈춘다
bash scripts/04-nvidia-toolkit.sh
bash scripts/verify/04-gpu.sh    # GPU 1차 관문 (Docker 컨테이너)
bash scripts/05-1-kind-cluster.sh   # kind 4노드 (GPU 1, CPU 2, control-plane 1)
bash scripts/05-2-gpu-node.sh       # GPU 노드 컨테이너에 toolkit, containerd 설정
bash scripts/05-3-device-plugin.sh  # device plugin (GPU 노드에만)
bash scripts/verify/05-3-device-plugin.sh   # GPU 2차 관문 (GPU 노드의 파드). 단계마다 verify/05-N-*.sh 가 있다
```

```bash
bash scripts/06-kubeflow.sh          # Pipelines, Notebooks, KServe (첫 설치는 이미지를 많이 받아 오래 걸린다)
bash scripts/verify/06-kubeflow.sh
```

단계별 확인은 `scripts/verify/`.

## 상태 (2026-10-23)

00~05 완료. kind 4노드(GPU 1, CPU 2, control-plane 1), GPU 2차 관문 통과 (GPU 노드의 파드에서 RTX 5080 확인). 06 Kubeflow 는 스크립트와 빌드 검증까지 끝났고 설치는 아직이다.
