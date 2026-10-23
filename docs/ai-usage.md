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

**한계**: Codex 는 실제 WSL/Docker/kind 환경에 접근하지 못했고, kind GPU 레시피는 어디서도 end-to-end 로 검증되지 않았다. 이 PC 에서의 실제 검증은 `verify/05-kind.sh` 가 한다.
