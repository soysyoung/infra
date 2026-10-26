# 생성형 AI 사용 기록

이 프로젝트는 생성형 AI(Claude Code)를 도구로 쓰되, **무엇을 AI 가 했고 무엇을 직접 했는지, 어떻게 검증했는지**를 기록한다.

## 역할 분담

| 영역 | AI | 직접 |
|---|---|---|
| 구조 제안, 대안 비교 | 초안과 근거 조사 | 방향 결정. 예: k3s 대신 kind 를 제안, 런타임 이중화 문제를 짚음 |
| 버전 선택 | 공식 릴리스 페이지 조사, 기준 제안 | 안정성 우선 원칙 지정, 최종 승인 |
| 스크립트 작성 | 초안 작성, 구문 검사 | 실제 WSL 에서 실행하고 결과 확인 |
| 문서화 | ADR, 버전 표 작성 | 사실 확인, 수정 요청 |
| 시스템 변경 (WSL, 관리자 권한) | 스크립트 작성만 | 관리자 PowerShell 에서 직접 실행 |

## AI 의 판단을 바로잡은 사례

- **kind 대 k3s**: AI 가 처음에 k3s 를 권했으나 사용자가 "containerd 와 Docker 엔진을 같이 쓰는 건 이 프로젝트에서 중요한 문제"라고 지적했다. 분석 결과 사용자 지적이 맞았고, Kubeflow 가 kind 를 공식 테스트 환경으로 쓴다는 근거도 확인되어 kind 로 변경했다 ([0002](decisions/0002-kind-over-k3s.md)).
- **Home 에디션의 Hyper-V**: 사용자가 Hyper-V 안내가 없다고 지적했다. Home 에는 Hyper-V 관리자가 없고 Virtual Machine Platform 만 필요해서, `00` 스크립트에 확인 단계를 추가했다.
- AI 가 만든 `[Console]::OutputEncoding` 설정이 스크립트 전체 출력을 깨뜨린 것을 실행해 보고 발견해 범위를 좁혔다 ([troubleshooting.md](troubleshooting.md) 3번).
- **근거 없는 값**: AI 가 inotify 한도를 근거 없이 1024 로 정했고, "답변이 불확실해서 신뢰가 안 간다"는 지적을 받았다. kind 공식 문서와 이 PC 실측(uid 0 이 131개 사용, 한도 128)으로 다시 확인해 공식 권장값 512 로 바로잡고, 메모리 비용처럼 확인하지 못한 부분은 모른다고 명시했다 ([troubleshooting.md](troubleshooting.md) 9번).
- **반복되는 수동 명령**: 복구 절차를 명령 여러 줄로 반복 안내하다가 "하나씩 치기 싫어서 스크립트화하는 것"이라는 지적을 받았다. 일회성 복구 스크립트를 따로 만들지 않고, 같은 경합이 inotify 없이도 생길 수 있다는 점을 근거로 `06` 의 정상 단계(Istio CNI 자가 복구)로 넣었다 (10번).
- **틀린 검증 기준**: AI 가 만든 `verify/06` 이 로그인 전 `/` 의 `HTTP 403` 을 실패로 판정했다. 응답 본문(Sign In 페이지)과 게이트웨이 로그(`ext_authz_denied`)를 읽어 정상 응답임을 확인하고 기준을 `/oauth2/start` 의 Dex 리다이렉트로 고쳤다 (15번).
- **AI 가 만든 깨진 파일**: AI 가 README 에 Windows 경로를 파이썬 문자열로 덧붙이다가 백슬래시가 이스케이프(탭, NUL)로 바뀌어 깨진 README 가 push 되었다. 사용자가 README 수정이 필요하다고 해서 열어 보다가 발견했고, 추적 파일 전체를 바이트 단위로 검사해 이 파일 한 개뿐임을 확인한 뒤 고쳤다 ([troubleshooting.md](troubleshooting.md) 19번).
- **공식 문서 없이 쓴 구성 (2026-10-23)**: 비밀번호 반영, port-forward 방식과 NodePort 방식, ADR 0009 를 AI 가 클론한 매니페스트와 기억으로 먼저 썼고, 사용자가 "공식 문서에 기반한 것이 맞느냐"고 묻자 아니라고 답했다. kind, kubectl, Service, systemd, dex 문서로 사후 대조해 [ADR 0009](decisions/0009-tailnet-exposure-port-forward-vs-nodeport.md) 에 표로 남겼고, 문서에 없던 `$2b$` 해시 접두사를 dex 예시와 같은 `$2y$` 로 맞췄다. 그 뒤 ADR 0010 은 쓰기 전에 대조했다.
- **틀린 주장**: AI 가 "이 PC 에서는 `powercfg` 로 덮개 설정이 조회되지 않는다"고 문서에 썼다. 사용자가 덮개 설정을 다시 확인해 달라고 해서 `powercfg /qh`(숨김 포함)로 조회해 보니 설정이 있었고 AC/DC 모두 "아무 것도 안 함" 이었다. `/query` 에는 안 나오는 숨김 설정이었고, 세 문서의 문장을 고쳤다 ([ADR 0010](decisions/0010-reboot-recovery.md)).
- **같은 실수의 재발**: 문서를 파이썬 문자열로 쓰다가 Windows 경로의 백슬래시 뒤 글자가 이스케이프로 해석되어 제어문자(BEL)가 들어갔다 (19번과 같은 원인). 쓴 직후의 바이트 검사에서 잡아 고쳤다. 검사를 습관으로 넣은 덕에 push 전에 발견했지만, 경로를 이스케이프하지 않는 쓰기 방식으로 바꾸지는 못했다.
- **커밋 컨벤션 위반**: 사용자가 컨벤션을 지키고 있는지 묻자 AI 가 실제 커밋으로 점검했다. 형식은 맞았지만 "한 커밋에 하나의 목적" 을 두 번 어겼다 (비밀번호, port-forward 방식, NodePort 방식을 한 커밋에 / `docs` 커밋에 코드 변경 포함). 이미 push 한 `dev` 는 force push 가 필요해서 고치지 않고 앞으로 나누기로 했다.
- **Codex 위임 실패**: main 병합을 Codex 에 맡겼으나 첫 시도는 `node` PATH ([troubleshooting.md](troubleshooting.md) 6번과 같은 원인), 두 번째는 Codex 샌드박스가 `.git` 에 쓰지 못해 실패했다. 우회하지 않고 사용자에게 선택지를 물어 AI 가 직접 실행했다.
- **공식 안내를 읽기 전에 만든 NodePort (2026-10-26)**: AI 가 tailnet 접속용으로 port-forward 와 NodePort 두 방식을 만들고 NodePort 를 선호안으로 두었다. 사용자가 "보통은 어떤 방식을 쓰느냐"고 묻자 AI 가 Kubeflow 공식 문서를 확인했고, 공식이 NodePort 를 권하지 않으며 localhost 가 아닌 주소에 HTTP 로 접속하면 웹앱이 깨진다는 것을 발견했다. 서버 쪽 `Set-Cookie: …; Secure` 로 확인한 뒤 NodePort 를 폐기하고 `tailscale serve` HTTPS 로 바꿨다. 이후 핸드폰에서 Notebook 생성이 통과했다 ([ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md)).
- **보고를 로그로 대조해 가설을 보류한 사례**: "시크릿 탭에서도 같은 오류"라는 보고가 쿠키 가설과 맞지 않아, AI 는 가설을 확정하지 않고 게이트웨이 로그를 대조했다 (쿠키 없는 요청은 정상, 핸드폰 요청은 전부 토큰이 붙은 요청이었고 시크릿 탭의 흔적은 없었다). 사용자가 "새 시크릿 탭" 으로 다시 해 보자 접속되어 원인이 옛 세션 쿠키로 확정됐고, 처음 실패는 열려 있던 시크릿 탭이 쿠키를 갖고 있었던 것으로 추정한다 ([troubleshooting.md](troubleshooting.md) 24번).
- **AI 자신의 진단 도구 실수**: `pkill -f` 가 자기 셸의 명령줄까지 매칭해 진단이 도중에 죽었고, `grep` 패턴이 JSON 공백을 놓쳐 빈 결과가 나왔다. 둘 다 출력이 비어 있는 것을 이상하게 여겨 원인을 찾았고, 비어 있는 결과를 "없다"로 해석하지 않았다.
- **사용자 설계 제안 반영**: 노드 수와 inotify 한도를 `cluster.env` 로 인자화하자는 제안을 받아들였다. AI 가 제안한 Kubeflow 스크립트 5단계 분리는 사용자가 철회해서 `kustomization.yaml` 하나를 유지했다.

## 검증 방식

- AI 가 쓴 주장은 가능한 한 공식 문서나 릴리스 페이지로 다시 확인하고, 확인하지 못한 것은 문서에 "미검증"으로 명시한다 ([versions.md](versions.md)).
- 단계마다 `scripts/verify/` 로 동작을 확인한다.
- 교차 리뷰: Codex(OpenAI) 로 스크립트를 독립 검토했다 (아래 결과). 두 번 실패한 뒤 성공했다 ([troubleshooting.md](troubleshooting.md) 6번).

## Codex 리뷰 결과 (2026-10-23)

Codex(GPT 계열, 읽기 전용)가 `00`, `03`, `04`, verify, 문서를 공식 문서와 대조했다. 보고서는 제안일 뿐이라서, 시스템 설정을 바꾸는 항목은 적용 전에 직접 확인했다 (nvkind README 의 명령, device plugin 릴리스, 다운로드 URL 응답).

| 지적 | 처리 |
|---|---|
| 04 가 kind GPU 에 부족: `--set-as-default --cdi.enabled`, `accept-nvidia-visible-devices-as-volume-mounts` 누락 | **반영.** nvkind README 에서 명령 확인. `04` 수정 |
| 03 의 `daemon.json` 처리가 재실행에 불안정 | **반영.** 이미 snapshotter 설정이 있으면 통과 |
| hold 때문에 버전 변경/다운그레이드 실패 | **반영.** `unhold` + `--allow-downgrades` 후 다시 hold |
| `wsl.exe` 실패가 PowerShell 에서 안 잡힘 | **반영.** 설치 호출 뒤 `$LASTEXITCODE` 확인 |
| Docker apt 키 `chmod a+r`, `gnupg` 누락 | **반영** |
| `vmIdleTimeout=-1` 은 문서에 없음 | **반영.** 주석을 고침. 상시 구동은 시작 작업으로 처리 |
| verify 의 인코딩 복원이 `finally` 가 아님 | **반영** |
| kind GPU 는 `/dev/dxg` bind mount 가 아니라 마커 마운트 | **반영.** 0006 과 `kind-config.yaml` |
| `containerd.io` 등은 pin/hold 안 됨 | **미반영.** 문서가 docker-ce 만 pin 이라고 쓰고 있어 과장은 아님. 필요해지면 추가 |
| 03 의 "이미 설치됨" 조기 종료 | **유지.** 같은 버전이 설치되어 있으면 끝내는 것이 의도. 설치가 중간에 끊긴 경우는 수동으로 처리 |

**한계**: Codex 는 실제 WSL/Docker/kind 환경에 접근하지 못했고, kind GPU 레시피는 어디서도 end-to-end 로 검증되지 않았다.

### 실행으로 드러난 Codex 레시피의 빈틈

Codex 의 kind GPU 레시피대로 구성한 뒤 `verify/05-kind.sh` 가 실패했다. 노드 컨테이너에서는 GPU 가 보이지만 노드가 `nvidia.com/gpu` 를 광고하지 않았다. device plugin 로그(`ERROR_LIBRARY_NOT_FOUND`)로 원인을 좁혔고, 레시피에는 **노드 안의 containerd 설정**이 빠져 있었다. NVIDIA nvkind 소스(`node.go`)를 직접 읽어 빠진 단계를 확인했고, 시험용 클러스터에서 먼저 시험한 뒤 스크립트에 넣어 처음부터 다시 만들어 통과를 확인했다. 두 번째 실패(device plugin Ready 직후의 타이밍)도 같은 방식으로 고쳤다.
교훈: 다른 모델의 조사 결과도 제안일 뿐이고, 마지막 판정은 이 PC 에서의 검증 스크립트가 한다. 그래서 검증 스크립트를 먼저 만들었다.
