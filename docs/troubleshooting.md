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
- 선택 기준은 [0004](decisions/0004-docker-single-runtime.md) 에 있다 (29.8.2).

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

## 미해결 / 확인 필요

- kind 안의 파드가 GPU 를 잡는지는 아직 검증하지 못했다 ([0006](decisions/0006-nvidia-wsl2-blackwell.md)). `verify/05-kind.sh` 로 확인한다.
