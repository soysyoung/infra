# infra

노트북(Windows 11 + WSL2 + RTX 5080)을 원격 MLOps 서버로 만드는 프로젝트. Tailscale, Docker, kind, Kubeflow 를 셸 스크립트로 설치하고, 이후 Terraform 으로 코드화한다.

- 구성도: [docs/architecture.md](docs/architecture.md)
- 버전과 선택 근거: [docs/versions.md](docs/versions.md), [docs/decisions/](docs/decisions/)
- 막힌 곳과 해결: [docs/troubleshooting.md](docs/troubleshooting.md)
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
bash scripts/05-kind.sh          # kind 클러스터 + device plugin
bash scripts/verify/05-kind.sh   # GPU 2차 관문 (kind 노드 안의 파드)
```

06 (Kubeflow) 는 2차 관문 통과 후 추가한다. 단계별 확인은 `scripts/verify/`.

## 상태 (2026-10-23)

00~03 완료, 04 는 Codex 리뷰 반영으로 수정되어 재실행 필요, 05 는 작성만 했고 실행 전.
