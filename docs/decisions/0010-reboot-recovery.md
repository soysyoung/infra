# 0010. 재부팅 후 자동 복구: 예약 작업, kind 재시작 정책, 전원 설정

- 상태: 구성함, **재부팅 시험 1회 통과** (구성 2026-10-23, 시험 2026-10-26). **2026-10-27 에 같은 경로가 실패했다** (컨트롤 플레인이 네트워크에서 떨어짐). 원인과 대책은 아래 '사고 기록', 대책은 아직 적용하지 않았다. 한계는 '아직 모르는 것'

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

## 재부팅 시험 결과 (2026-10-26, 1회)
'다시 시작' 으로 재부팅했다. 시각(KST): Windows 부팅 10:27:15 -> `wsl-keepalive` 실행 10:27:36 -> 바탕화면 10:27:41 -> WSL VM, `tailscaled` 10:27:50 -> kind 노드 4개 10:27:52 -> Kubeflow 게이트웨이와 dex Ready 10:28:43. 08 은 통과했고 출력은 [verify/README.md](../../scripts/verify/README.md).

- S4U 로 실행한 `wsl.exe` 가 배포판을 띄웠다 (확인). 작업이 바탕화면보다 먼저 돌았다. 다만 이 PC 는 비밀번호가 없어 자동으로 로그인되므로 '로그온 세션이 아예 없는 상태' 까지는 확인하지 못했다.
- 노드 컨테이너가 사람의 조작 없이 시작됐다 (`unless-stopped`, `docker inspect` 의 StartedAt 이 WSL 시작 2초 뒤).
- `tailscaled` 가 노드보다 먼저 떠서 API 서버(tailnet 주소 바인딩)도 문제없었다. **1회 관찰이라 순서가 보장된다는 뜻은 아니다.**
- 노드 IP 변경으로 클러스터가 깨지지 않았다 (노드 4개 모두 Ready).

## 아직 모르는 것
- 윈도우 비밀번호 로그인 화면이 있는 상태, 시작 메뉴 '종료' 후 전원 켜기(빠른 시작 `HiberbootEnabled=1`), 덮개를 닫은 채의 동작.
- `sleep infinity` 프로세스가 유휴 종료를 막는지. 작업이 없던 기간에도 WSL 이 2일 넘게 켜져 있었으므로 켜진 뒤 유지에는 필요 없을 수 있다. 재부팅 뒤 WSL 을 띄우는 역할은 이 작업이 했다.

## 사고 기록: 컨트롤 플레인이 kind 네트워크에서 떨어져 8080 이 막힘 (2026-10-27)
위 시험은 통과했지만 '순서가 보장된다는 뜻은 아니다' 라고 적은 위험이 그대로 일어났다. 위험 자체는 시험 전에도 알려져 있었다 ([kind-config.yaml](../../k8s/kind-config.yaml) 의 `shortcut:` 주석, [ADR 0009](0009-tailnet-exposure-port-forward-vs-nodeport.md) 표, [archive/troubleshooting-2026-10-23.md](../archive/troubleshooting-2026-10-23.md) 71행).

**증상.** `http://localhost:8080` 이 연결되지 않았다. `kubeflow-port-forward` 서비스가 `The connection to the server <tailnet IP>:6443 was refused` 로 120번 넘게 재시작했다. 노드 컨테이너 중 `mlops-control-plane` 만 `Restarting (1)` 이었고 로그는 `ERROR: have an old IPv4 address but no current IPv4 address (!)` 였다.

**확인한 것** (이 PC 의 `docker inspect`, `docker events`, `journalctl -u docker -u tailscaled`):
- 컨트롤 플레인은 `kind` 네트워크에 연결된 곳이 없었다 (`Networks: {}`, `docker network inspect kind` 의 Containers 가 비어 있었다). 워커 3개는 같은 시각에 정상으로 붙었다.
- 컨트롤 플레인의 게시 포트는 호스트 IP 가 tailnet 주소다: `6443/tcp -> <tailnet IP>`, `30080/tcp -> <tailnet IP>` (`docker inspect` 의 PortBindings, 실행 중에는 `docker-proxy -host-ip <tailnet IP> -host-port 6443` 프로세스). 워커에는 게시 포트가 없다.
- `docker.service` 에 `tailscaled` 와의 순서 지정이 없다 (`After=` 에 없고 `/etc/systemd/system/docker.service.d` 도 없다).
- 이 PC 의 WSL 은 오늘 8번 시작했다 (09:57, 10:48, 11:08, 11:33, 11:51, 13:30, 13:40, 13:41). 컨트롤 플레인이 네트워크에 붙은 마지막 부팅은 10:48 이고 (`sbJoin ep=mlops-control-plane`), 11:08 부팅부터 붙지 못했다. 그 뒤 모든 부팅이 같다.
- 11:08 부팅의 시각 (KST): Docker 시작 11:08:23 -> 컨트롤 플레인 샌드박스 복원 실패 `error locating sandbox id 8a885a42...: not found` 11:08:24.318 -> `tailscaled` 가 `NoState -> Starting` 으로 가고 `tailscale0` 에 `<tailnet IP>` 이 생김 11:08:24. 즉 Docker 가 컨트롤 플레인의 엔드포인트를 복원하던 순간과 tailnet 주소가 생기는 순간이 같은 초였다.
- 한 번 떨어진 뒤에는 `docker stop/start` 만으로 되돌아오지 않았다 (워커 먼저/나중 두 순서를 시도). 이전 네트워크 샌드박스가 사라져서 부팅마다 같은 실패를 반복한 것으로 보이나 내부 동작은 확인하지 않았다.

**원인 (정황이 강하지만 직접 증거는 없다).** 컨트롤 플레인만 호스트 IP 가 tailnet 주소인 포트를 게시하는데, Docker 가 그 컨테이너를 복원하는 시점에 `tailscale0` 에 그 주소가 아직 없어서 호스트 쪽 바인딩이 실패하고, 엔드포인트가 만들어지지 않았다고 본다. 같은 조건에서 워커는 정상이었다는 점, 호스트에 없는 IP 로 게시하면 바인딩이 실패한다는 일반적인 동작과 맞다 (Docker 공식 문서가 아니라 [일반 설명](https://www.golinuxcloud.com/cannot-assign-requested-address/) 으로만 확인). **`journalctl` 에 바인딩 오류 문장이 없다.** 그래서 확정이 아니라 가설이다. 이 가설이 틀렸다면 아래 1번 대책으로 재발하는지 보고 판단한다.
- 10-26 시험이 통과한 이유: 그때는 `tailscaled` 가 Docker 보다 먼저 떴다 (이 ADR 의 시험 결과). 10-27 의 다른 부팅들에서 `tailscaled` 와 Docker 의 선후는 11:08 외에는 확인하지 않았다.
- 모르는 것: 오늘 WSL 이 8번 시작한 이유(수동 종료인지, 유휴 종료인지)와, 10-26 시험에서 순서가 맞았던 이유가 우연인지 구조인지.

**복구 (2026-10-27 실행).** 전부 멈추고 컨트롤 플레인을 `172.18.0.4` 로 `kind` 네트워크에 다시 붙인 뒤(`docker network disconnect -f` + `docker network connect --ip`) 컨트롤 플레인만 시작하고, 그다음에 워커를 시작했다. 노드 4개가 Ready 가 되었고, `kubeflow-port-forward` 가 active 가 되어 `http://localhost:8080/oauth2/start` 가 Dex 로 302 리다이렉트했다. 로그인과 Notebook 화면은 확인하지 않았다. 스크립트는 아직 저장소에 없다.

**고려한 방법과 판단** (대책은 모두 **미적용**, 효과는 모두 미시험):
| # | 방법 | 효과와 한계 | 판단 |
|---|---|---|---|
| 1 | `docker.service` drop-in 에 `ExecStartPre=/usr/bin/tailscale wait --timeout=...` | `tailscale wait` 는 tailscaled 가 Running 이고 `tailscale0` 가 올라와 IP 가 붙을 때까지 기다린다. 이 PC 의 1.104.2 에 있고, 도움말이 "바인딩하는 서비스가 쓰라" 고 안내한다. 원인(경합)을 직접 막는다. 시간 제한 안에 안 되면 Docker 는 그냥 시작한다 | **채택 후보** |
| 2 | drop-in 에 `After=/Wants=tailscale-online.target` | 같은 효과지만 `tailscale-wait-online.service` 에 `--timeout` 이 없어서 Tailscale 이 로그아웃·키 만료 상태면 Docker 가 영원히 못 뜬다. 시간 제한이 없는 점이 1번보다 나쁘다 | 기각 |
| 3 | `tailscaled.service` 에 `Before=docker.service` | 시작 순서만 보장하고 IP 가 붙는 시점은 보장하지 않는다. 10-27 13:41 부팅에서 `tailscaled` 는 13:41:45 에 시작했지만 `tailscale0` 에 주소가 보인 것은 13:41:47 이고 Docker 는 13:41:47 에 복원을 시작했다 | 기각 |
| 4 | 컨트롤 플레인이 떨어졌는지 보고 되붙이는 감시 서비스 (1분마다) | 1번의 시간 제한이 지났거나 다른 이유로 떨어진 경우를 복구한다. 원인을 없애지는 않는다. `kind` 네트워크에서 컨트롤 플레인이 빠진 것을 감지하면 위 복구 절차를 한다. `tailscale0` 에 주소가 없으면 시작이 또 실패하므로 그때는 다음 주기로 미룬다 | **채택 (1번과 함께)** |
| 4b | 같은 감시 서비스가 `127.0.0.1:8080` 이 2번 연속 무응답이고 API 서버(`/livez`)가 정상이면 `kubeflow-port-forward` 를 재시작 | `kubectl port-forward` 가 연결이 끊긴 채 종료하지 않고 멈추는 경우가 있다는 일반적 알려진 동작에 대비한다 (이 PC 에서 관찰한 것은 아님). 임의로 정한 1분 주기이고 복구 시간 보장이 아니라 최대 대기 시간이다 | **채택** |
| 4c | port-forward 가 API 서버를 tailnet 주소 대신 컨트롤 플레인 컨테이너 IP(`https://172.18.0.4:6443`)로 부름 | 같은 PC 안의 접속이 `tailscale0` 와 물리 NIC 에 의존하지 않게 한다. 인증서 SAN 에 `172.18.0.4` 가 있고 `https://172.18.0.4:6443/livez` 가 200 인 것을 실측했다. 컨테이너 IP 가 바뀌면 인증서와 맞지 않아 접속이 안 되므로 IP 를 고정해야 한다 | **채택** |
| 5 | `sysctl net.ipv4.ip_nonlocal_bind=1` | 존재하지 않는 IP 에도 바인딩을 허용해 경합 자체를 없앨 수 있다. 그러나 `docker-proxy` 가 이 설정으로 정말 성공하는지, 그 뒤 트래픽이 정상인지 시험하지 않았다. 호스트 전체의 바인딩 규칙을 바꾸는 부작용이 있다 | 보류 (시험 전에는 쓰지 않는다) |
| 6 | `apiServerAddress` 를 `127.0.0.1` 로, 30080 매핑을 없애기 | kind 문서가 "강하게 권장" 하는 기본값이고 ([kind 문서](https://kind.sigs.k8s.io/docs/user/configuration/)) tailnet 바인딩이 아예 없어져 원인이 사라진다. 원격 `kubectl` 은 `tailscale serve --tcp` 등으로 다시 열어야 한다 (미시험). 클러스터 생성 시에만 정해지므로 **클러스터를 새로 만들어야 한다** (Kubeflow 재설치) | 장기 대안. Terraform 전환 때 함께 한다 |
| 7 | `apiServerAddress: 0.0.0.0` | LAN 에도 노출된다. [ADR 0012](0012-official-doc-recheck.md) 발견 1 과 kind 문서가 피하라는 방향 | 기각 |
| 8 | Docker `live-restore` | 데몬이 재시작해도 컨테이너를 유지하는 기능이다. WSL 이 통째로 내려가는 이번 경우에는 해당하지 않는다 (`live-restore=false` 실측) | 기각 |
| 9 | Docker 시작 전 `sleep N` | 임의 대기이고 보장이 없다 | 기각 |

**네트워크 전환(이더넷/와이파이)에 대해 로그로 본 것.**
- 오늘 부팅마다 기본 경로가 `eth0`, `eth1`, `eth2` 로 달랐고, `tailscaled` 가 `fixupWSLMTU: default route is not via eth0` 경고를 냈다. 이 경고가 불안정을 일으키는지는 확인하지 않았다.
- `kubeflow-port-forward` 는 API 서버를 tailnet 주소(`<tailnet IP>:6443`)로 불러서 같은 PC 안의 접속이 `tailscale0` 에 의존했다. 10:49 부팅에서 `dial tcp <tailnet IP>:6443: no route to host` 가 나왔고, 그때 `tailscaled` 는 `tailscale0` 링크를 못 찾는 로그를 남겼다. 이전 판단("NIC 가 바뀌어도 port-forward 는 영향이 없다")은 틀렸고 4c 가 이를 고친다.
- 오늘 실패 8번 중 7번은 컨트롤 플레인 문제였고 `no route to host` 는 1번이었다. 와이파이 부팅처럼 네트워크가 늦게 올라와 `tailscale0` 가 늦어져 11:08 의 경합이 생겼을 수 있으나 증명하지 못했다.
- 사용자 보고 (2026-10-27): 이더넷과 와이파이를 바꿀 때마다 `wsl --shutdown` 후 WSL 을 다시 시작하면 접속이 돌아왔다. 현재의 우회책이다. 이 우회는 매번 부팅 경로(Docker 복원과 `tailscale0` 의 경합)를 다시 타므로, 1·4 번 대책이 없으면 11:08 같은 실패가 그때마다 날 수 있다. 전환 때 WSL 이 새 NIC 를 못 따라가는 이유는 확인하지 않았다 (미확인).
- 한계: 핸드폰이 쓰는 `tailscale serve` 주소는 Tailscale 에 의존하므로 NIC 전환 중 잠깐 끊기는 것은 막을 수 없다.

**공식 문서 대조 (2026-10-27).** 방법마다 근거 수준이 다르다.
| 대상 | 공식 문서가 말하는 것 | 이 구성 | 판정 |
|---|---|---|---|
| `tailscale wait` | 바인딩하려는 서비스가 Tailscale 이 준비될 때까지 기다리는 용도, `--timeout`, 시간 초과는 0 이 아닌 종료 코드, systemd 는 `tailscale-online.target` ([Tailscale CLI](https://tailscale.com/docs/reference/tailscale-cli)) | `docker.service` 의 `ExecStartPre=-tailscale wait --timeout=60` | 일치 |
| `ExecStartPre` 의 `-`, 빈 `ExecStart=` | `-` 접두사가 없는 명령이 실패하면 유닛이 실패. 빈 문자열을 대입하면 앞선 시작 명령 목록이 초기화된다 ([systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)) | 시간 초과여도 Docker 는 시작, port-forward drop-in 이 `ExecStart=` 를 비우고 다시 지정 | 일치 |
| `tailscale-online.target` 기각 사유 | `Type=oneshot` 은 시작 시간 제한이 기본으로 꺼져 있다 (같은 문서). `tailscale-wait-online.service` 는 `Type=oneshot` 이고 `--timeout` 이 없다(이 PC 의 유닛 파일) | Tailscale 이 로그아웃이면 무한 대기 | 일치 (기각 사유가 확인됨) |
| `docker network connect --ip` | 지정한 IP 는 정지된 컨테이너를 다시 시작할 때 다시 적용되고, 그 IP 를 쓸 수 없으면 컨테이너가 시작하지 못한다 ([Docker](https://docs.docker.com/reference/cli/docker/network/connect/)) | 컨트롤 플레인 IP 를 `.4` 로 고정 | 일치. **새로 알게 된 위험**: 부팅 때 다른 컨테이너가 `.4` 를 먼저 쓰면 컨트롤 플레인이 시작에 실패한다 -> 감시 서비스가 '붙어 있지만 2번 연속 실행 중이 아님' 도 복구하도록 고쳤다 |
| 재시작 정책 | 정책은 컨테이너가 정상적으로 시작한 뒤에 적용된다. 수동으로 멈춘 컨테이너는 데몬이 재시작될 때까지 재시작하지 않는다. 컨테이너에 의존하는 호스트 프로세스가 있으면 systemd 같은 프로세스 관리자를 쓰라고 하며, **Docker 재시작 정책과 호스트 프로세스 관리자를 함께 쓰면 충돌한다고 경고한다** ([Docker](https://docs.docker.com/engine/containers/start-containers-automatically/)) | 감시 서비스가 노드를 수동으로 `stop/start` 하고 재시작 정책 `unless-stopped` 도 둔다 | **부분 불일치.** 공식이 권하는 방식은 노드 컨테이너를 systemd 유닛(`After=tailscale-online.target`)으로 직접 시작하고 재시작 정책을 끄는 것(아래 10번). 이번에는 시도하지 않았다 |
| `apiServerAddress` | 기본값(127.0.0.1)을 유지하라고 "강하게 권장" ([kind 설정](https://kind.sigs.k8s.io/docs/user/configuration/)) | 6번을 장기 대안으로 둠. 지금은 tailnet 주소 | 현 구성은 권고와 다르다 ([ADR 0012](0012-official-doc-recheck.md) 발견 1) |
| 호스트에 없는 IP 로 게시하면 바인딩 실패 | Docker 공식 문서에서는 찾지 못했다. 일반 설명 글만 있다 | 원인 가설의 근거 | **미확인** |
| 컨테이너 IP 로 API 서버 접속(4c) | kind 문서에 이런 접속법은 없다. Linux 에서 Docker Desktop 없이는 호스트에서 노드 IP 로 바로 보낼 수 있다는 문장만 있다 | 실측으로만 확인 (SAN, `/livez` 200) | **공식 근거 없음, 내 설계** |
| 감시 서비스(4, 4b), `kubectl port-forward` 가 멈춘 채 안 끝나는 경우 | 공식 문서를 찾지 못했다 | 4b 의 근거는 일반 지식 | **내 설계 / 미확인** |

10. (추가 방법) 노드 컨테이너를 systemd 유닛으로 직접 관리: `After=tailscale-online.target`, `docker start -a`, `docker update --restart=no`. Docker 문서가 재시작 정책 대신 권하는 방식이고 순서도 직접 표현된다. 대신 노드 4개의 유닛과 의존 관계를 만들어야 하고 `kind` 가 만든 컨테이너와의 충돌을 시험해야 한다. 감시 서비스(4)가 실제로 충돌을 일으키면 이쪽으로 바꾼다.

**적용.** 1 + 4 + 4b + 4c 를 [scripts/08-boot-resilience.sh](../../scripts/08-boot-resilience.sh) 한 스크립트로 만들었다 (`sudo` 필요, 사용자가 실행). **아직 실행하지 않았고 모든 효과가 미시험이다.** 6 은 Terraform 전환 때 한다. 실행한 뒤에는 이더넷만/와이파이만/네트워크 없이 부팅했다가 나중에 연결/실행 중 전환을 시험하고 8080 이 복구되기까지 걸린 시간을 이 문서에 기록한다.

**대책 시험 결과.**
- 2026-10-27 15:01 부팅(1차): `tailscale wait` 가 1초 미만에 `status=0` 으로 끝났다. `tailscaled` 가 먼저 올라와 있어서 대기가 필요했는지는 알 수 없다. 이 시험 전의 14:53 부팅에서는 `--timeout=60` (단위 없음) 때문에 `invalid value "60" for flag -timeout` 으로 즉시 실패했다. `-` 접두사 때문에 Docker 가 그냥 떠서 눈에 띄지 않았고, 이후 `--timeout=60s` 로 고치고 스크립트가 같은 명령을 직접 실행해 보게 했다.
- 2026-10-27 15:13 부팅(2차, 사용자 보고로 와이파이 접속, 기본 경로 `eth3`): `ExecStartPre` 가 15:13:33 에 시작해 15:13:36 에 `status=0` 으로 끝났다 (3초 대기). 같은 시각에 `tailscaled` 가 15:13:34 `NoState -> Starting`, 15:13:36 `Starting -> Running` 으로 가고 `tailscale0` 에 `<tailnet IP>` 이 생겼다. Docker 는 15:13:36.51 에 시작했다. 즉 대기가 `tailscale0` 의 주소가 생길 때까지 Docker 를 늦췄다. 컨트롤 플레인은 `172.18.0.4` 로 kind 네트워크에 붙었고 노드 4개가 올라왔으며, 감시 서비스는 개입하지 않았고 `127.0.0.1:8080` 이 302 로 응답했다.
- 2026-10-27 15:18 부팅(3차, 사용자가 네트워크 없이 `wsl --shutdown` 후 시작하고 15:19 에 이더넷을 연결): `tailscaled` 로그에 `fixupWSLMTU: could not get default route: network is unreachable` 와 DERP 연결 `network is unreachable` 이 있어 오프라인 부팅이 맞다. 그런데도 `Starting -> Running` 이 15:18:35 에 되고 `tailscale wait` 는 15:18:36 에 같은 시각으로 `status=0` 이었다. **오프라인에서도 `tailscale wait` 는 대기하지 않고 통과한다** (cached 상태로 Running 이 되고 `tailscale0` 에 주소가 붙는 듯하나 내부 동작은 확인하지 않았다). 따라서 60초 시간 초과 경로는 시험하지 못했다. 기본 경로는 15:19:18 에 `eth1` 로 나타났다 (부팅 44초 뒤).
  - `kubeflow-port-forward` 는 부팅 직후 2번 실패(`connection to the server 172.18.0.4:6443 was refused`, 클러스터가 아직 올라오는 중)한 뒤 15:18:49 에 `Forwarding from 127.0.0.1:8080` 에 도달했다. 네트워크가 돌아오기(15:19:18) **29초 전**이다. 4c(컨테이너 IP 로 API 접속)가 없었다면 같은 조건에서 tailnet 주소로 불렀을 것이라 직접 비교는 못 했다.
  - 사용자가 붙인 터미널 A 출력은 15:19:30~15:19:44 의 8번 모두 302 였다. 네트워크가 생긴 지 12~26초 뒤부터의 기록이고 그 앞 구간(15:18:49~15:19:30)은 첨부되지 않았다.
  - 감시 서비스는 개입하지 않았다 (컨트롤 플레인이 정상으로 붙어서 필요 없었다). 즉 이 부팅까지 **감시 서비스의 복구 경로는 한 번도 실행된 적이 없었다** (아래 4차 시험에서 처음 실행됨).
- 감시 서비스 복구 경로 시험(4차, 2026-10-27 15:34~15:39, [scripts/verify/08-boot-resilience.sh](../../scripts/verify/08-boot-resilience.sh) 의 `detach` 와 `down`, 사용자가 실행). 스크립트가 출력한 시간은 받지 못했고 아래는 `docker events` 와 `journalctl -u mlops-watchdog` 에서 읽은 값이다. 감시는 1분 주기가 아니라 약 66초 간격으로 돌았다 (15:30:11, 15:31:26, 15:32:38, 15:33:44, 15:34:50, 15:35:59, 15:37:06, 15:38:12). 타이머에 `AccuracySec=10s` 를 둔 영향으로 짐작하나 확인하지 않았다.
  - `detach` (모든 노드 정지 + 컨트롤 플레인을 네트워크에서 뗌): 15:34:01 정지 시작, 15:34:12 컨트롤 플레인이 `kind` 네트워크에서 떨어진 상태 완성 -> 15:34:50 감시가 `kind 네트워크에서 빠짐 -> 172.18.0.4 로 다시 붙임` -> 15:34:53 컨트롤 플레인 시작 -> 15:34:59~15:35:00 워커 3개 시작 -> 15:35:00 `복구 완료`. 정지 시작부터 컨테이너 복구까지 59초 (감시가 돌기를 기다린 38초 포함). 사람 조작 없음.
  - `down` (컨트롤 플레인만 정지): 15:35:59 정지 시작, 15:36:12 정지 -> 15:37:06 `실행 중이 아님 (1/2)` -> 15:38:12 두 번째 확인에서 복구 시작 (워커 3개도 함께 정지) -> 15:38:26 컨트롤 플레인 시작 -> 15:38:30~31 워커 시작 -> 15:38:31 `복구 완료`. 정지 시작부터 2분 32초. 설계대로 '2번 연속' 확인을 거쳤다. 멀쩡한 워커도 같이 내렸다 올라오는 점, `docker stop` 이 10초 안에 안 끝나는 워커를 강제 종료한 점(15:38:12~22)도 이 경로의 비용이다.
  - 두 경우 모두 컨트롤 플레인이 `172.18.0.4` 로 돌아왔고 노드 4개가 Ready, `127.0.0.1:8080` 이 302 로 응답했다 (15:40 현재). `kubeflow-port-forward` 는 복구 직후 `Forwarding` 에 도달했다가 몇 번 `lost connection to pod` 로 재시작한 뒤 안정됐다 (`detach` 15:35:04~15:35:45, `down` 15:38:38~15:39:17). 감시 서비스의 오류 기록은 없다.
  - 한계: 사고의 원인(경합)을 재현한 것이 아니라 복구 코드만 시험했다. 8080 이 끊긴 시간은 기록하지 못했다 (port-forward 가 연결을 다시 맺은 시각까지가 근거). 복구 중 `tailscale0` 에 주소가 없을 때 미루는 분기는 시험하지 못했다.
- 실행 중 NIC 전환(d): 사용자가 여러 번 했다고 보고했고, `tailscaled` 의 `LinkChange` 로그에 실행 중 전환이 최소 2번 남아 있다. 14:52:06 `eth3 -> eth1` (14:49 부팅, `08` 적용 후), 15:13:08 `eth1 -> eth3` (15:01 부팅). 두 번 다 전환 뒤 `kubeflow-port-forward` 에 오류나 재시작이 없었다. **그러나** 관찰 구간이 각각 약 25초, 16초뿐이다. 사용자가 전환 뒤 곧바로 `wsl --shutdown` 을 해서 부팅이 끝났기 때문이다. 이 구간의 `8080` 응답 코드는 기록이 없고 서비스 로그만 근거이며, `kubectl port-forward` 가 로그 없이 멈추는 경우는 로그로 알 수 없다. 처음에 "전환 시험은 안 한 셈"이라고 판단한 것은 붙여 준 출력과 한 부팅만 보고 한 오판이었다.
- 별도 관찰: `kubeflow-port-forward` 의 `error: lost connection to pod` 가 NIC 변화와 무관하게 거의 모든 부팅 직후(예: 14:49:46, 14:53:44, 15:02:07, 15:14:30)에 반복된다. 서비스는 5초 뒤 다시 `Forwarding` 에 도달했다 (재시작 카운터가 부팅 직후 1~2분에 6~7까지 올라간 부팅도 있다). 원인은 확인하지 않았다 (게이트웨이 파드가 기동 중에 재시작하는 것으로 짐작하지만 미확인).
- 한계: 부팅 3번의 결과이고, 11:08 의 실패 부팅과 같은 조건을 재현한 것은 아니다. 대기가 없었다면 실패했을 것이라는 증명은 못 했다. 원인 가설(`tailscale0` 의 주소가 늦어 Docker 가 포트를 게시하지 못함)이 맞다는 직접 증거도 아니다. 아직 안 한 시험: 네트워크 없이 부팅했다가 나중에 연결(60초 시간 초과 경로와 감시 서비스의 복구), 실행 중 전환.

## 시험 절차
1. 관리자 PowerShell: `windows\autostart.ps1`, `windows\power-settings.ps1`
2. WSL: `bash scripts/05-1-kind-cluster.sh` (재시작 정책 적용, 멱등)
3. Windows 재부팅 후 **로그인하지 않고** 몇 분 기다린다.
4. 다른 기기에서 `http://<tailnet 주소>:8080` 접속 확인, 그리고 로그인한 뒤 WSL 에서 `bash scripts/verify/08-reboot.sh`
