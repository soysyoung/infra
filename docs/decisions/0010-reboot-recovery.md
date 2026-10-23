# 0010. 재부팅 후 자동 복구: 예약 작업, kind 재시작 정책, 전원 설정

- 상태: 구성함, **재부팅 시험 전** (2026-10-23)

## 상황
원격 서버로 쓰려면 재부팅(윈도우 업데이트, 정전)이나 유휴 뒤에 사람이 로그인하지 않아도 Kubeflow 접속이 돌아와야 한다. 확인한 사실:

- WSL 은 쓰는 사람이 없으면 꺼진다 (`vmIdleTimeout` 기본 60000ms). 부팅 직후에는 WSL 이 떠 있지 않아 `tailscaled`, Docker, `kubeflow-port-forward` 서비스도 없다.
- 이 PC 의 kind 노드 컨테이너 4개의 재시작 정책은 모두 `on-failure:1` 이다 (`docker inspect` 실측). Docker 문서에 따르면 `on-failure` 는 **데몬이 재시작되면 컨테이너를 다시 시작하지 않는다.** 그대로면 재부팅 후 노드가 올라오지 않는다.
- 노트북이라 AC 전원에서도 절전으로 들어가면 서버가 멈춘다.

## 결정
| 문제 | 해결 | 위치 |
|---|---|---|
| 부팅 직후 WSL 이 없음 | 시스템 시작 때 로그온 없이 `wsl.exe -d Ubuntu-24.04 --exec /usr/bin/sleep infinity` 를 도는 예약 작업 `wsl-keepalive` | `windows/autostart.ps1` (관리자) |
| 노드가 재시작되지 않음 | 클러스터를 만든 뒤 `docker update --restart unless-stopped` 를 노드에 적용 (이미 만든 클러스터도 `05-1` 재실행으로 적용) | `scripts/05-1-kind-cluster.sh` |
| AC 절전 | `powercfg /change standby-timeout-ac 0`, `hibernate-timeout-ac 0` | `windows/power-settings.ps1` (관리자) |
| 확인 | 서비스, 재시작 정책, 노드 Ready, 파드, tailnet 접속 | `scripts/verify/08-reboot.sh` |
| 삭제 | `wsl-keepalive` 작업 제거 | `scripts/teardown/00-windows-wsl.ps1` |

## 공식 문서 대조 (2026-10-23)
| 대상 | 공식 문서가 말하는 것 | 이 구성 | 판정 |
|---|---|---|---|
| 재시작 정책 | `on-failure` 는 데몬이 재시작되어도 컨테이너를 다시 시작하지 않는다. `unless-stopped` 는 수동으로 멈추지 않은 한 데몬 재시작 뒤 다시 시작한다. `docker update --restart unless-stopped <이름>` 으로 실행 중인 컨테이너의 정책을 바꾼다 ([Docker](https://docs.docker.com/engine/containers/start-containers-automatically/)) | 노드에 `unless-stopped` | 일치 |
| 트리거 | `-AtStartup`: 시스템이 시작될 때 작업을 시작 ([문서](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger)) | `-AtStartup` | 일치 |
| S4U | 비밀번호를 시스템이 저장하지 않고, **네트워크와 암호화된 파일에 접근할 수 없다** ([문서](https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype)) | `-LogonType S4U`, `-RunLevel Limited` | 일치 (제약은 아래 미검증) |
| 실행 시간 | 기본은 시작 72시간 뒤 중지, `PT0S` 는 무제한 ([문서](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-executiontimelimit)) | `-ExecutionTimeLimit ([TimeSpan]::Zero)` | 일치 (PowerShell 의 Zero 가 PT0S 로 저장되는지는 등록 후 작업 XML 로 확인하지 않았다) |
| `vmIdleTimeout` | VM 이 유휴일 때 종료까지의 시간, 기본 60000ms ([문서](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)) | 옵션은 건드리지 않음 | "유휴"의 정의와 `sleep` 프로세스가 이를 막는지는 문서에 없다 (아래 미검증) |
| `powercfg /change` | `standby-timeout-ac`, `hibernate-timeout-ac` 가 있고 값은 분 ([문서](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)) | 둘 다 0 | 일치 (0 이 "안 함"이라는 문장은 추출된 문서에 없었다. 실행 후 `powercfg /query` 로 확인) |

## 미검증 (재부팅 시험으로 확인)
- S4U 로 부팅 때 실행한 `wsl.exe` 가 배포판을 띄우고 유지하는지. S4U 는 네트워크 접근이 없다고 하지만 WSL 의 네트워크는 VM 의 것이라 영향이 없을 것으로 **추정**한다.
- `sleep infinity` 프로세스가 유휴 종료를 막는지.
- 재부팅 후 `tailscaled` 가 Docker 보다 늦게 떠서 kind API 서버(tailnet 주소 바인딩)나 노드 컨테이너가 시작에 실패하는지 ([troubleshooting.md](../troubleshooting.md) 열린 항목).
- 재시작 뒤 kind 노드의 IP 가 바뀌어 클러스터가 깨지는지.
- 덮개를 닫았을 때의 동작: 이 PC 의 전원 구성표에서 `powercfg` 로 덮개 설정이 조회되지 않았다 (`SUB_BUTTONS` 아래에는 시작 메뉴 전원 단추뿐). 제어판 '덮개를 닫을 때 수행할 작업' 을 직접 확인해야 한다.

## 시험 절차
1. 관리자 PowerShell: `windows\autostart.ps1`, `windows\power-settings.ps1`
2. WSL: `bash scripts/05-1-kind-cluster.sh` (재시작 정책 적용, 멱등)
3. Windows 재부팅 후 **로그인하지 않고** 몇 분 기다린다.
4. 다른 기기에서 `http://<tailnet 주소>:8080` 접속 확인, 그리고 로그인한 뒤 WSL 에서 `bash scripts/verify/08-reboot.sh`
