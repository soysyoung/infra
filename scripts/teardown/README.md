# 삭제 스크립트

설치의 **역순**으로 지운다. 설치 스크립트(`scripts/NN-*.sh`)와 번호가 대응한다. 되돌릴 수 없으므로 모든 스크립트가 `yes` 입력을 요구하고, `DRY_RUN=1`(PowerShell은 `-DryRun`)이면 아무것도 실행하지 않고 실행할 명령만 출력한다.

| 순서 | 스크립트 | 지우는 것 | 순서가 중요한 이유 |
|---|---|---|---|
| 1 | `06-kubeflow.sh` | 공식 저장소 클론(`~/.cache/infra`), kustomize | Kubeflow 워크로드는 클러스터 안에 있어서 2번에서 함께 사라진다 |
| 2 | `05-kind-cluster.sh` | kind 클러스터(Kubeflow, device plugin, GPU 노드 설정 포함), kind, kubectl, inotify 설정 | Docker 가 살아 있어야 `kind delete cluster` 가 노드 컨테이너를 지울 수 있다 |
| 3 | `04-nvidia-toolkit.sh` | NVIDIA Container Toolkit, apt 저장소 | `daemon.json` 을 03 상태로 먼저 되돌리고 Docker 를 재시작한 뒤 패키지를 지운다. 거꾸로 하면 Docker 가 없어진 nvidia 런타임을 찾다가 시작에 실패한다 |
| 4 | `03-docker.sh` | Docker Engine, 이미지/컨테이너/볼륨, apt 저장소, docker 그룹 멤버십 | 위 둘이 Docker 를 쓰므로 마지막에 지운다 |
| 5 | `02-tailscale.sh` | Tailscale 연결 해제와 제거 | **원격 접속이 끊긴다.** 맨 뒤에 둬서 앞 단계를 원격에서 끝낼 수 있게 한다 |
| 6 | `00-windows-wsl.ps1` (PowerShell) | Ubuntu-24.04 배포판(안의 모든 데이터), `.wslconfig`(백업으로 이름 변경) | 배포판을 지우면 01(`/etc/wsl.conf`)도 함께 사라진다 |

## 사용

```bash
# WSL 안에서: 1~5 를 한 번에 (sudo 비밀번호는 한 번만 묻는다)
DRY_RUN=1 bash scripts/teardown/all.sh   # 먼저 무엇을 지우는지 확인
bash scripts/teardown/all.sh
```

```powershell
# Windows PowerShell 에서: 6
powershell -ExecutionPolicy Bypass -File .\scripts\teardown\00-windows-wsl.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\scripts\teardown\00-windows-wsl.ps1
```

각 스크립트는 따로 실행할 수도 있다. 이미 지워진 항목은 건너뛰므로 다시 실행해도 안전하다.

## 지우지 않는 것

- **Tailscale 관리 콘솔의 장치 항목**: 직접 삭제한다 (https://login.tailscale.com/admin/machines). 오래된 장치가 쌓이면 ACL/SSH 적용 시 섞일 수 있다.
- **WSL 플랫폼과 Virtual Machine Platform 기능**: 다른 용도로 쓸 수 있어 그대로 둔다 (끄는 명령은 `00-windows-wsl.ps1` 머리말).
- 이 저장소의 파일, NVIDIA 드라이버(Windows 쪽), `~/.bashrc` 의 사용자 설정.
- `sysctl` 의 inotify 값은 설치 전 이 PC 의 기본값(128)으로 되돌린다. 다른 PC 에서는 기본값이 다를 수 있다.
