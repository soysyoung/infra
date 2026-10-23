# 문제 해결 기록

실제로 막힌 것과 해결을 표로 정리한다. 번호는 고정이고(다른 문서가 번호로 참조한다), 새 항목은 아래에 이어서 추가한다.
1~9번의 상세 기록(진단 로그, 명령, 교훈)은 [archive/troubleshooting-2026-10-23.md](archive/troubleshooting-2026-10-23.md) 의 같은 번호 절에 있다.

상태: **해결** = 원인을 확인하고 고쳤다 / **우회** = 동작하지만 원인은 모른다 / **미조치** = 사용자 작업이 남았다 / **확인 중** = 결과를 기다린다.

| # | 증상 | 원인 | 해결 | 상태 | 상세 |
|---|---|---|---|---|---|
| 1 | WSL 없는 PC 에서 `wsl --version` 이 `Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG` | 모름 (일반 권한과 관리자 권한의 차이였을 수 있다) | `00-windows-wsl.ps1` 이 WSL 설치를 처리. 관리자 권한으로 다시 실행하자 오류 없이 진행됨 | 우회 | [1](archive/troubleshooting-2026-10-23.md) |
| 2 | `.\scripts\00-... 인식되지 않습니다`, `#requires ... 관리자 권한` | 현재 폴더가 `projects` 였음. VS Code 터미널은 관리자 권한이 아님 | `cd` 로 `infra` 이동, 관리자 PowerShell 에서 `-ExecutionPolicy Bypass` 를 한 번만 붙여 실행 | 해결 | [2](archive/troubleshooting-2026-10-23.md) |
| 3 | PowerShell 에서 `wsl.exe` 출력이 깨짐. 한글이 든 `.ps1` 이 깨짐 | `wsl.exe` 는 UTF-16 출력. Windows PowerShell 5.1 은 BOM 없는 UTF-8 을 잘못 읽음 | `wsl` 호출 구간에만 `OutputEncoding` 을 바꿈. `.ps1` 은 UTF-8 BOM 으로 저장 | 해결 | [3](archive/troubleshooting-2026-10-23.md) |
| 4 | `03-docker.sh` 가 목록만 보여주고 멈춤 | `DOCKER_VERSION` 이 비어 있음 (의도한 동작) | 선택 기준에 따라 29.8.2 지정 ([ADR 0004](decisions/0004-docker-single-runtime.md)) | 해결 | [4](archive/troubleshooting-2026-10-23.md) |
| 5 | `tailscale status` 에 offline 노드 7개 (마지막 접속 248~335일 전) | 쓰지 않는 예전 장치가 같은 계정에 남아 있음. SSH/ACL 적용 시 섞일 수 있음 | Tailscale 관리 콘솔에서 직접 삭제 | 미조치 | [5](archive/troubleshooting-2026-10-23.md) |
| 6 | Codex 리뷰가 두 번 실패 (`node: command not found`, `Codex CLI is not installed`) | Node.js 미설치, 이어서 설치 전에 시작된 세션의 PATH 가 낡음 | 호출 앞에 `export PATH="/c/Program Files/nodejs:.../npm:$PATH"`. 세션을 재시작하면 불필요 | 해결 | [6](archive/troubleshooting-2026-10-23.md) |
| 7 | Git Bash 에서 `wsl.exe -- bash /mnt/c/...` 가 `C:/Program Files/Git/mnt/c/...` 로 바뀜 | MSYS 가 경로를 자동 변환 | `MSYS_NO_PATHCONV=1` 을 앞에 붙임 | 해결 | [7](archive/troubleshooting-2026-10-23.md) |
| 8 | `verify/05` 실패: 노드가 `nvidia.com/gpu` 를 광고하지 않음. device plugin 로그에 `Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND` | 호스트 Docker 의 nvidia 런타임은 노드 컨테이너까지만 GPU 를 넣음. 노드 안의 containerd 는 runc 라서 파드에 못 넣음 (Codex 레시피에 없던 단계) | 노드 안에 toolkit 설치 + containerd 를 nvidia 런타임으로 설정 (`05-2`). 이어서 device plugin Ready 직후 용량 반영 지연은 검증에 60초 대기 | 해결 | [8](archive/troubleshooting-2026-10-23.md) |
| 9 | Kubeflow 설치 중 `istio-cni-node` 가 4개 노드 모두 `CrashLoopBackOff`: `couldn't initialize inotify: too many open files`. 처음 보인 오류는 kserve 웹훅 `connection refused` | WSL 의 `fs.inotify.max_user_instances` 가 128. 실측 uid 0 이 131개 사용. kserve 웹훅 오류는 컨트롤러 기동 지연이 낳은 증상 | 512 로 상향 (kind 공식 권장값, [cluster.env](../cluster.env) 의 `INOTIFY_MAX_USER_INSTANCES`, `05-1` 이 `/etc/sysctl.d` 에 기록) | 해결 | [9](archive/troubleshooting-2026-10-23.md) |
| 10 | 사이드카가 붙는 파드가 `Init:Error` 에서 멈추고 스스로 복구되지 않음 (`istio-validation`: `iptables validation failed`) | CNI 가 Ready 가 되기 전에 스케줄된 파드. CNI 와 워크로드를 한 번에 적용하면 inotify 와 무관하게도 생기는 경합 | `06` 이 적용 후 CNI Ready 를 보장하고(필요하면 재시작) `Init:Error`/`Init:CrashLoopBackOff` 파드만 지움. 실행에서 4개 파드가 재생성됨을 확인 | 해결 | - |
| 11 | `06` 이 `error: no matching resources found` 로 중단되어 `kubeflow` 네임스페이스를 기다리지 못함 | `kubeflow-system` 에 Deployment 가 없는데 `kubectl wait --for=condition=Available deployment --all` 을 걸었음. `wsl.exe` 를 거쳐 `echo $?` 로 찍은 종료 코드는 에러가 났는데도 `0`, 다음 실행에서는 빈 값이어서 신뢰할 수 없었다 (파일에 기록하면 정확했다). 원인 **미확인** | Deployment 가 없는 네임스페이스는 건너뜀 (`06`, `verify/06`). 재실행에서 `kubeflow` 네임스페이스까지 대기를 통과 | 해결 | - |
| 12 | `metadata-grpc`, `ml-pipeline` 이 `CrashLoopBackOff` (`mysql_real_connect failed`, `unexpected EOF`) | MySQL 파드가 10번 때문에 `Init:Error` 였고, 재생성된 뒤에도 의존 파드는 재시도 간격 때문에 늦게 따라옴 | 별도 조치 없이 재실행에서 두 파드 모두 Available 로 복구됨 | 해결 | - |
| 13 | `git add` 마다 `LF will be replaced by CRLF` 경고 | Windows 의 `core.autocrlf` 가 체크아웃 시 CRLF 로 바꿈. WSL 의 bash 는 CRLF 스크립트를 못 읽음 | `.gitattributes` 로 `*.sh`, `*.env` 를 LF 로 고정 | 해결 | - |
| 14 | `wsl.exe -u root` 에서 `Failed to start the systemd user session for 'root'` 경고 | 모름 (출력은 정상이었고 영향은 확인하지 못함) | 없음 | 우회 | - |
| 15 | `verify/06` 이 `HTTP 403` 으로 실패 | 로그인 전 `/` 의 403 (`UAEX ext_authz_denied`)은 oauth2-proxy 의 Sign In 페이지로 가는 정상 응답. 검증 기대값(200/30x)이 틀렸음 | `/oauth2/start` 가 `/dex/auth` 로 리다이렉트하는지로 확인 | 해결 | - |
| 16 | 새 WSL 셸에서 `kubectl get po` 가 멈추거나 `No resources found in default namespace` | 처음에 kubeconfig 를 `--kubeconfig ~/.kube/kind-mlops.yaml` 로 따로 써서(kind 공식 기본값은 `~/.kube/config` 에 병합) `kubectl` 이 기본 `localhost:8080` 으로 접속을 시도함. 연결이 되어도 `default` 네임스페이스에는 파드가 없음 (Kubeflow 는 `kubeflow` 등 다른 네임스페이스) | **공식 기본값으로 전환**: `--kubeconfig`, `KUBECONFIG` export, `.bashrc` 수정을 모두 제거. 스크립트는 `kubectl --context kind-mlops` 를 명시하는 함수(`common.sh`)로 다른 클러스터가 생겨도 엉뚱한 곳에 적용되지 않게 함. 파드는 `kubectl get po -A` | 해결 | - |

## 열린 항목

- 재부팅 후 tailscaled 와 Docker 의 기동 순서. API 서버가 tailnet 주소에 바인딩되어 있어서 tailscaled 가 늦으면 노드 컨테이너가 시작에 실패할 수 있다. `windows/autostart.ps1` 단계에서 확인한다.
- `/etc/sysctl.d` 의 inotify 설정이 재부팅 후에도 유지되는지 (systemd 가 켜져 있어 유지될 것으로 보나 확인하지 않았다).
- 클러스터를 지우면 GPU 노드 안의 toolkit 설치와 containerd 설정이 사라진다. `05-2` 가 매번 다시 하지만 외부 apt 저장소가 필요하다.
- Kubeflow 기본 로그인(user@example.com / 12341234)의 비밀번호 변경. 로그인 후 기능(Pipelines 실행, Notebook 생성, GPU Notebook)은 아직 시험하지 않았다.
