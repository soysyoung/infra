# 삭제 스크립트

설치의 **역순**으로 지운다. 설치 스크립트(`scripts/NN-*.sh`)와 번호가 대응한다. 되돌릴 수 없으므로 모든 스크립트가 `yes` 입력을 요구하고, `DRY_RUN=1`(PowerShell은 `-DryRun`)이면 아무것도 실행하지 않고 실행할 명령만 출력한다.

| 순서 | 스크립트 | 지우는 것 | 순서가 중요한 이유 |
|---|---|---|---|
| 0-1 | `08-boot-resilience.sh` | 감시 서비스 `mlops-watchdog`(타이머, 서비스, `/usr/local/sbin/mlops-watchdog`, `/etc/mlops`), 이전 버전이 만든 `docker.service` drop-in 과 전용 kubeconfig | 클러스터가 사라지면 할 일이 없고 컨트롤 플레인 IP 기록이 낡은 값이 되므로 먼저 지운다 |
| 0-2 | `07-1-port-forward.sh` | systemd 서비스 `kubeflow-port-forward` | 클러스터가 사라지면 접속할 곳이 없어 재시작만 반복하므로 먼저 지운다. `07-3` 의 `tailscale serve` 설정은 따로 지우지 않는다: 02 의 `tailscale logout` 과 `/var/lib/tailscale` 삭제와 함께 사라진다(추정, 시험 전). 하나만 끄려면 `sudo tailscale serve --https=443 off` |
| 1 | `06-kubeflow.sh` | 공식 저장소 클론(`~/.cache/infra`), kustomize | Kubeflow 워크로드는 클러스터 안에 있어서 2번에서 함께 사라진다 |
| 2 | `05-kind-cluster.sh` | kind 클러스터(Kubeflow, device plugin, GPU 노드 설정 포함), kind, kubectl, inotify 설정 | Docker 가 살아 있어야 `kind delete cluster` 가 노드 컨테이너를 지울 수 있다 |
| 3 | `04-nvidia-toolkit.sh` | NVIDIA Container Toolkit, apt 저장소 | `daemon.json` 을 03 상태로 먼저 되돌리고 Docker 를 재시작한 뒤 패키지를 지운다. 거꾸로 하면 Docker 가 없어진 nvidia 런타임을 찾다가 시작에 실패한다 |
| 4 | `03-docker.sh` | Docker Engine, 이미지/컨테이너/볼륨, apt 저장소, docker 그룹 멤버십 | 위 둘이 Docker 를 쓰므로 마지막에 지운다 |
| 5 | `02-tailscale.sh` | Tailscale 연결 해제와 제거 | **원격 접속이 끊긴다.** 맨 뒤에 둬서 앞 단계를 원격에서 끝낼 수 있게 한다 |
| 6 | `00-windows-wsl.ps1` (PowerShell) | 예약 작업 `wsl-keepalive`(있으면), Ubuntu-24.04 배포판(안의 모든 데이터), `.wslconfig`(백업으로 이름 변경) | 배포판을 지우면 01(`/etc/wsl.conf`)도 함께 사라진다 |

## 사용

```bash
# WSL 안에서: 0~5 를 한 번에 (sudo 비밀번호는 한 번만 묻는다)
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

## 삭제 확인

삭제가 끝났는지 명령으로 확인한다. 아래 "기대 결과"가 나오면 정상이다.

### WSL 안 (`all.sh` 직후)

```bash
docker --version; kind version; kubectl version --client; kustomize version; tailscale version
dpkg -l | grep -E 'docker|nvidia-container|tailscale'
ls /etc/docker /var/lib/docker /var/lib/containerd /var/lib/tailscale ~/.cache/infra
sysctl -n fs.inotify.max_user_instances
ip link show docker0
grep -c kind-mlops ~/.kube/config
```

| 명령 | 기대 결과 |
|---|---|
| `docker`, `kind`, `kubectl`, `kustomize`, `tailscale` 실행 | 모두 `command not found` |
| `dpkg -l \| grep ...` | 출력 없음 |
| `ls /etc/docker ...` | 모두 `No such file or directory` |
| `sysctl -n fs.inotify.max_user_instances` | `128` |
| `ip link show docker0` | `Device "docker0" does not exist` |
| `grep -c kind-mlops ~/.kube/config` | `0` |

**실제로 확인한 상태 (2026-10-23, 첫 삭제 직후)**: 실행 파일, 디렉터리, apt 저장소 파일, inotify(128), kind 항목(0)은 위 기대 결과와 같았다. 다만 패키지 `docker-ce-rootless-extras`, `tailscale-archive-keyring` 가 남았고 `docker0` 장치가 `active` 로 남아 있었다. 이 잔재는 삭제 스크립트를 고쳤지만 **고친 경로는 아직 시험하지 못했다.** 위 표는 수정 후의 기대 결과이고, 다음 삭제 때 실제 출력으로 교체한다.

### Windows (`00-windows-wsl.ps1` 직후)

```powershell
wsl --list --verbose
Test-Path $env:USERPROFILE\.wslconfig
Get-ChildItem $env:USERPROFILE\.wslconfig.bak-* | Select-Object Name
```

**실제 출력 (2026-10-23):**

```text
PS> wsl --list --verbose
(설치된 배포가 없다는 안내. 'wsl.exe --list --online' 으로 목록을 보고 'wsl.exe --install <Distro>' 로 설치하라는 내용)
(종료 코드: -1)

PS> Test-Path $env:USERPROFILE\.wslconfig
False

PS> Get-ChildItem $env:USERPROFILE\.wslconfig.bak-* | Select-Object Name
Name
----
.wslconfig.bak-20261023-193007
```

- 배포판이 하나도 없으면 `wsl --list --verbose` 는 **빈 표가 아니라 안내 메시지를 내고 종료 코드 -1** 로 끝난다. 이것이 정상이다. (배포판이 남아 있으면 `Ubuntu-24.04` 가 표에 나온다.)
- 안내 메시지의 한글 원문은 콘솔 인코딩 문제로 정확히 옮기지 못해 내용만 적었다.

### 직접 확인할 것

Tailscale 관리 콘솔(https://login.tailscale.com/admin/machines)에서 이 장치가 사라졌는지 본다. 명령으로 확인할 수 없다.

## 출력 예시

아래는 모두 이 저장소의 실제 환경(Windows 11 Home, WSL2 Ubuntu 24.04)에서 2026-10-23 에 실행한 결과다. **아래 드라이런과 취소 경로는 2026-10-23 출력이다.** 실제 삭제는 2026-10-27 에 한 번 실행했다 (아래 '실제 삭제 실행').

### 실제 삭제 실행 (2026-10-27, `DRY_RUN=1` 확인 후 `all.sh`)
작동 중이던 클러스터를 지웠고 사용자가 출력을 붙여 준 것에서 읽었다. 모든 단계(08, 07-1, 06, 05, 04, 03, 02)가 오류 없이 `==> 완료` 로 끝났다. 그 뒤에 사용자가 `00-windows-wsl.ps1` 도 실행했고, Windows 쪽 확인(배포판 없음 안내와 종료 코드 -1, `.wslconfig` 없음, 백업 `.wslconfig.bak-20261027-160036`, 예약 작업 `wsl-keepalive` 없음)은 기대와 같았다.
- 08: 감시 서비스와 이전 버전 흔적 7개를 지우고 `mlops-watchdog.timer` 의 `timers.target.wants` 링크를 제거했다.
- 05: `Deleted nodes: ["mlops-worker" "mlops-worker2" "mlops-worker3" "mlops-control-plane"]`, `fs.inotify.max_user_instances = 128`.
- 03: `docker-ce-rootless-extras` 와 `docker-compose-plugin` 포함 6개 패키지를 제거했다 (2026-10-23 에 남았던 `docker-ce-rootless-extras` 가 이번에는 제거됨). `dpkg: warning: directory '/etc/docker' not empty so not removed` 는 purge 단계의 경고이고, 스크립트의 `rm -rf /etc/docker` 가 이어서 처리한다 (실제 삭제 여부는 배포판을 지워 확인하지 못했다). `Disabling 'docker.service', but its triggering units are still active: docker.socket` 는 `docker.socket` 도 같은 명령에서 비활성화해서 무해한 경고로 보인다.
- 02: `tailscale` 과 `tailscale-archive-keyring` 를 제거했다. `tailscale logout` 의 출력은 없어서 성공 여부를 모른다 (스크립트는 `|| true`). 관리 콘솔의 장치는 직접 지워야 한다.
- **확인하지 못한 것:** `sudo ip link delete docker0` 의 결과, 그리고 WSL 안의 '삭제 확인' 표 전체 (뒤이어 배포판을 지워서). 자동 설치된 의존 패키지(`iptables`, `nftables`, `pigz` 등)는 `sudo apt autoremove` 안내만 나오고 지우지 않는다 (배포판 전체를 지우면 상관없다).

### 드라이런: `DRY_RUN=1 bash scripts/teardown/all.sh`

`[dry-run]` 줄이 실제로 실행될 명령이다. 이미 지워진 항목은 `...설치되어 있지 않아 건너뜁니다.` 로 나온다.

```text
다음을 설치의 역순으로 삭제합니다:
  06  Kubeflow 설치용 클론, kustomize
  05  kind 클러스터(Kubeflow 와 모든 데이터 포함), kind, kubectl, inotify 설정
  04  NVIDIA Container Toolkit, Docker 런타임 설정
  03  Docker Engine (이미지, 컨테이너, 볼륨 포함)
  02  Tailscale 연결 해제와 제거 (원격 접속이 끊깁니다)
==> 삭제 06-kubeflow
[dry-run] rm -rf /home/soysyoung/.cache/infra
[dry-run] sudo rm -f /usr/local/bin/kustomize
==> 완료
==> 삭제 05-kind-cluster
[dry-run] kind delete cluster --name mlops
[dry-run] sudo rm -f /usr/local/bin/kind /usr/local/bin/kubectl
[dry-run] sudo rm -f /etc/sysctl.d/99-kind-inotify.conf
[dry-run] sudo sysctl -w fs.inotify.max_user_instances=128
==> 완료
==> 삭제 04-nvidia-toolkit
[dry-run] sudo sh -c echo '{"features": {"containerd-snapshotter": false}}' > /etc/docker/daemon.json
[dry-run] sudo systemctl restart docker
[dry-run] sudo apt-mark unhold nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
[dry-run] sudo apt-get purge -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
[dry-run] sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
==> 완료
==> 삭제 03-docker
[dry-run] sudo systemctl disable --now docker.service docker.socket containerd.service
[dry-run] sudo apt-mark unhold docker-ce docker-ce-cli
[dry-run] sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
[dry-run] sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
[dry-run] sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc
[dry-run] sudo gpasswd -d soysyoung docker
==> 완료
==> 삭제 02-tailscale
[dry-run] sudo tailscale logout
[dry-run] sudo systemctl disable --now tailscaled
[dry-run] sudo apt-get purge -y tailscale
[dry-run] sudo rm -rf /var/lib/tailscale /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg
==> 완료. 관리 콘솔에서 이 장치를 직접 삭제하세요.
==> WSL 안의 삭제 완료. Windows 쪽은 scripts\teardown\00-windows-wsl.ps1 을 실행하세요.
```

- `sudo sh -c echo '{...}' > ...` 줄은 드라이런이 인자를 이어 붙여 출력한 모양이다. 실제로는 `sh -c` 에 한 덩어리 인자로 전달되어 올바른 JSON 이 쓰이는 것을 임시 파일로 확인했다.

### 취소

확인 입력이 `yes` 가 아니면 아무것도 지우지 않고 종료 코드 1 로 끝난다. 앞뒤 공백과 대소문자는 무시하지만 `y` 같은 약식은 받지 않는다 (파괴적 작업이라 일부러 엄격하게 두었다).

```text
$ echo no | bash scripts/teardown/06-kubeflow.sh
오류: 취소했습니다.

$ bash scripts/teardown/06-kubeflow.sh < /dev/null
오류: 입력이 없어 취소했습니다.
```

### Windows 드라이런: `-DryRun`

```text
[dry-run] wsl --terminate Ubuntu-24.04
[dry-run] wsl --unregister Ubuntu-24.04
[dry-run] Move-Item C:\Users\pc_18\.wslconfig C:\Users\pc_18\.wslconfig.bak-20261023-191839
완료. Tailscale 관리 콘솔에서 이 장치를 삭제했는지 확인하세요.
```

`.wslconfig` 는 지우지 않고 `.bak-<날짜-시간>` 으로 이름만 바꾼다.

## 설계 근거와 공식 문서 대조

순서와 안전장치의 이유, 그리고 각 삭제 명령을 공식 문서와 대조한 결과는 [ADR 0008](../../docs/decisions/0008-teardown-order-and-doc-check.md) 에 있다.

## 문제가 생기면

- **`apt-get purge` 가 잠금 오류**: 다른 apt 가 실행 중이다. 잠시 뒤 다시 실행한다 (이미 지운 항목은 건너뛴다).
- **Docker 가 시작하지 않는다 (04 이후)**: `/etc/docker/daemon.json` 에 없는 `nvidia` 런타임이 남아 있는 경우다. 04 삭제는 이를 먼저 되돌리지만, 수동으로 지웠다면 `sudo rm /etc/docker/daemon.json && sudo systemctl restart docker`.
- **`sudo` 비밀번호를 계속 묻는다**: `all.sh` 는 시작할 때 한 번 묻는다. 개별 스크립트는 각각 묻는다.
