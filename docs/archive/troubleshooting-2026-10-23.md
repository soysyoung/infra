> **아카이브** (2026-10-23 시점의 상세 기록). 현재 요약표는 [../troubleshooting.md](../troubleshooting.md) 이고, 번호(1~9)는 표와 같다.
> 이 파일은 수정하지 않는다. 새 항목은 표에 추가하고 필요하면 상세를 새 아카이브로 남긴다.

# 문제 해결 기록

실제로 막힌 것과 해결을 시간순으로 적는다.

## 1. `wsl --version` 이 `Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG`

- 증상: WSL 이 없는 PC 에서 `wsl --version` 이 클래스 미등록 오류를 낸다.
- 해결: `scripts/00-windows-wsl.ps1` 이 WSL 설치를 처리한다. 관리자 권한으로 다시 실행했을 때는 이 오류 없이 진행되어 Ubuntu 설치까지 갔다.
- 원인은 확인하지 못했다. 일반 권한과 관리자 권한의 차이였을 수 있다.

## 2. 스크립트 실행 오류: 경로와 관리자 권한

- `.\scripts\00-windows-wsl.ps1 : ... 인식되지 않습니다`: 현재 폴더가 `projects` 였고 스크립트는 `projects\infra` 아래에 있었다. -> `cd` 로 `infra` 로 이동한다.
- `#requires ... 관리자 권한으로 실행하기 위한`: VS Code 터미널은 관리자 권한이 아니다. -> 관리자 PowerShell 을 새로 열어 실행한다 (`Start-Process powershell -Verb RunAs ...`).
- PowerShell 기본 정책이 스크립트를 막을 수 있어 `-ExecutionPolicy Bypass` 를 한 번만 붙여 실행한다. 시스템 설정은 바꾸지 않는다.

## 3. PowerShell 출력이 깨짐

- 증상: `wsl.exe` 의 출력이 `t И ...` 같은 문자로 나온다.
- 원인: `wsl.exe` 는 UTF-16 으로 출력한다.
- 해결: `wsl` 호출 동안에만 `[Console]::OutputEncoding = Unicode` 로 바꾼다. 처음에는 스크립트 전체에 적용해서 스크립트 자신의 한글 출력까지 깨졌다. 호출 구간으로 좁혀 해결했다.
- `.ps1` 에 한글이 있으면 Windows PowerShell 5.1 은 BOM 없는 UTF-8 을 잘못 읽는다. -> UTF-8 **BOM** 으로 저장한다.

## 4. Docker 설치 가능한 패치 선택

- `03-docker.sh` 는 `DOCKER_VERSION` 이 비어 있으면 29.x 목록을 보여주고 멈춘다. 의도한 동작이다.
- 선택 기준은 [0004](../decisions/0004-docker-single-runtime.md) 에 있다 (29.8.2).

## 5. 오래된 Tailscale 장치

- `tailscale status` 에 같은 계정의 offline 노드가 다수 남아 있다 (마지막 접속 248~335일 전). Tailscale SSH/ACL 적용 시 섞일 수 있어 관리 콘솔에서 정리가 필요하다.

## 6. Codex 리뷰가 두 번 실패

- 1차: Node.js 미설치로 `node: command not found`.
- 2차: Node.js 를 설치했지만 이 세션이 설치 **전에** 시작되어 Git Bash 의 PATH 에 `node` 와 npm 전역 경로(`%APPDATA%\npm`)가 없었다. `Codex CLI is not installed` 로 실패.
- 해결: 호출 앞에 `export PATH="/c/Program Files/nodejs:/c/Users/pc_18/AppData/Roaming/npm:$PATH"` 를 붙였다. 세션을 재시작하면 PATH 가 갱신되어 필요 없다.
- 교훈: 설치 직후에는 실행 중인 프로세스의 환경 변수가 낡았다는 점을 먼저 의심한다.

## 7. WSL 호출 시 Git Bash 가 경로를 변환

- `wsl.exe -- bash /mnt/c/...` 를 Git Bash 에서 부르면 `/mnt/c/...` 가 `C:/Program Files/Git/mnt/c/...` 로 바뀐다.
- 해결: `MSYS_NO_PATHCONV=1` 을 앞에 붙인다. WSL 안에서 직접 실행하면 해당 없음.

## 8. kind 에서 GPU 가 광고되지 않음 (device plugin 이 NVML 을 못 찾음)

- (당시에는 `05-kind.sh` 하나였고, 이후 `05-1`~`05-3` 으로 나눴다 — [0007](../decisions/0007-multi-node-kind.md))
- 증상: `verify/05-kind.sh` 가 `노드가 nvidia.com/gpu 를 광고하지 않습니다` 로 실패. 노드 컨테이너의 `nvidia-smi -L` 은 성공.
- 진단: device plugin 파드가 `Error` 로 재시작을 반복하고, 로그에 `Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND`.
- 원인: 호스트 Docker 의 nvidia 런타임은 **노드 컨테이너**에 GPU 를 주입하지만, 노드 안의 containerd 는 일반 runc 라서 **파드**에는 GPU 라이브러리를 넣지 못한다. Codex 의 레시피는 이 단계가 빠져 있었다("nvidia 가 기본 런타임이면 runtimeClassName 이 필요 없다"는 호스트 Docker 기준 설명이었다).
- 해결: NVIDIA nvkind 소스(`pkg/nvkind/node.go`)에서 노드 후처리를 확인했다. 노드 안에 toolkit 을 설치하고 `nvidia-ctk runtime configure --runtime=containerd --config-source=file --set-as-default --cdi.enabled` 후 containerd 를 재시작한다. `05-kind.sh` 에 넣었다. 클러스터를 지우고 처음부터 다시 만들어 검증했다.
- 이어서 생긴 문제: 새 클러스터에서 device plugin 이 Ready 가 된 직후 `verify/05` 가 다시 실패했다. kubelet 이 GPU 용량을 반영하기까지 몇 초 걸리는 타이밍 문제였고, 검증에 최대 60초 대기를 넣었다.

## 9. Kubeflow 설치 중 `istio-cni-node` 가 죽고 파드들이 `Init:Error` (inotify 한도)

- 증상: `06-kubeflow.sh` 의 적용 재시도 로그에 `failed calling webhook "clusterservingruntime.kserve-webhook-server.validator" ... connection refused`.
- 진단: 웹훅 오류는 증상이다 (kserve 컨트롤러가 인증서 Secret 이 생기기 전이라 늦게 떴다). 더 근본적으로 `kube-system` 의 `istio-cni-node` 가 4개 노드 전부에서 `CrashLoopBackOff` 였다.
  - `kubectl -n kube-system logs <istio-cni-node-...> --previous` -> `installer failed: ... couldn't initialize inotify: too many open files`
  - 사이드카가 붙는 파드의 `istio-validation` 초기화 컨테이너: `iptables validation failed; workload is not ready for Istio` (CNI 가 없는 노드에 먼저 스케줄됨)
  - `sysctl fs.inotify.max_user_instances` = **128** (WSL 기본값, kind 노드 컨테이너 안에서도 같은 값)
- 원인: kind 노드 컨테이너는 WSL 커널을 공유한다. 4노드와 kubelet/containerd 가 inotify 인스턴스 한도(128)를 소진했다.
- 근거: kind 공식 문서(Known Issues)가 같은 증상(`too many open files`)을 인용하며 Ubuntu 기본값 `max_user_instances=128`, `max_user_watches=8192` 가 "여러 노드의 클러스터에는 부족하다"고 하고 **`max_user_instances=512`**, `max_user_watches=524288` 을 권장한다. `inotify(7)` 는 두 한도를 "real user ID 당" 상한이라고 정의한다. 이 PC 실측(root 로 `/proc/*/fd` 를 센 값): uid 0 이 inotify 인스턴스 **131개**를 쓰고 있어 한도 128 을 이미 넘겼다 (watch 는 1168개로 한도 524288 에 한참 못 미침).
- 해결: `fs.inotify.max_user_instances` 를 (값은 [cluster.env](../../cluster.env) 의 `INOTIFY_MAX_USER_INSTANCES`, 기본 512) `/etc/sysctl.d/99-kind-inotify.conf` 에 두어 영구 적용하고 (`05-1-kind-cluster.sh` 에 넣었다, `verify/05-1` 이 값을 확인), `istio-cni-node` 를 재시작한 뒤 CNI 없이 만들어진 파드를 지워 다시 만들게 했다. Istio CNI 설정에 `cni.repair.deletePods=true` 가 없으면 이런 파드는 수동으로 지워야 한다.
- 교훈: 노드 수를 늘리기 전의 단일 노드 검증(`verify/05-*`)으로는 이 한도 문제가 드러나지 않았다. Kubeflow 가 처음으로 Istio CNI 를 올리면서 드러났다.

## 미해결 / 확인 필요

- 재부팅 후 tailscaled 와 Docker 의 기동 순서 (API 서버가 tailnet 주소에 바인딩되어 있다). `windows/autostart.ps1` 단계에서 확인한다.
- 클러스터를 지우면 노드 안의 toolkit 설치와 containerd 설정이 사라진다. `05-2-gpu-node.sh` 가 다시 하므로 문제는 없지만 외부 apt 저장소가 필요하다.
