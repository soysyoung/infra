# TODO

앞으로 할 일과 시험할 것. 끝낸 항목은 지우지 않고 결과를 적어 남긴다. 막힌 곳은 [troubleshooting.md](troubleshooting.md), 결정 근거는 [decisions/](decisions/).
`[ ]` 아직 안 함, `[x]` 끝남 (결과 기록).

## 재부팅 후 자동 복구 시험 (1회 통과) ([ADR 0010](decisions/0010-reboot-recovery.md))

구성은 끝났고(2026-10-23) 시험 전이다. 순서대로 한다.

- [x] 관리자 PowerShell: `windows\autostart.ps1` (부팅 때 WSL 을 띄우는 예약 작업 `wsl-keepalive`) -> 등록됨 (2026-10-26: 상태 Ready, 로그온 S4U, **한 번도 실행되지 않음**: 마지막 결과 0x41303 = 아직 실행 전)
- [x] 관리자 PowerShell: `windows\power-settings.ps1` (AC 절전 끄기). 실행 후 `powercfg /query` 로 값 확인 -> AC 절전/최대 절전 0 확인 (`powercfg /query`, 2026-10-26)
- [x] 덮개 닫기 동작: 제어판에서 '아무 것도 안 함' 으로 설정, `powercfg /qh SCHEME_CURRENT SUB_BUTTONS LIDACTION` 으로 AC/DC 모두 0 확인 (2026-10-23). 덮개를 닫은 채로도 접속되는지는 재부팅 시험 때 같이 본다
- [x] WSL: `bash scripts/05-1-kind-cluster.sh` (노드 재시작 정책 `unless-stopped` 적용, 멱등) -> 4개 노드 모두 `unless-stopped` 확인 (08 출력)
- [x] Windows 다시 시작 -> 2026-10-26 10:27:15 부팅. 이 PC 는 윈도우 비밀번호가 없어 로그인 화면 없이 바탕화면까지 자동으로 들어간다 (AutoAdminLogon=0 이지만 암호 없는 계정)
- [x] 08 실행 (10:32, WSL 가동 4분): 서비스 3개 active, 노드 4개 Ready, 재시작 정책 unless-stopped, port-forward 방식 OK. 출력은 [verify/README.md](../scripts/verify/README.md)
- [x] 확인할 위험 (1회 시험): S4U 작업이 로그온 없이 `wsl.exe` 를 띄웠다 (작업 10:27:36 < 바탕화면 10:27:41 < WSL 10:27:50, `sleep infinity` 프로세스 실행 중) / `tailscaled`(10:27:50) 가 노드(10:27:52) 보다 먼저 떠서 API 서버 바인딩이 문제 없었다 / 재시작 뒤 노드가 모두 Ready

2026-10-26 재부팅 시험 결과 (이 PC 에서 직접 조회, KST): Windows 부팅 10:27:15 -> `wsl-keepalive` 실행 10:27:36 -> 바탕화면 10:27:41 -> WSL VM/tailscaled 10:27:50 -> kind 노드 4개 10:27:52 -> oauth2-proxy Ready 10:28:04, 게이트웨이/dex Ready 10:28:43 -> VS Code 시작 10:29:24.
- 서비스와 Kubeflow 는 VS Code 보다 40초 먼저 준비됐다. 사용자는 "VS Code 를 열자 핸드폰 접속이 됐다" 고 했지만, 부팅 후 약 90초는 파드가 올라오는 중이라 그 사이 접속이 안 된 것으로 보인다 (시도 시각은 모른다).
- 이번 시험이 증명하지 못하는 것: (1) 윈도우 로그인 화면(비밀번호)이 있는 상태에서도 작업이 도는가 -- 이 PC 는 자동 로그인이라 바탕화면이 5초 뒤에 생겼을 뿐 작업이 먼저 돌았다는 것까지만 확인. (2) 시작 메뉴의 '종료' 후 전원 켜기(빠른 시작, `HiberbootEnabled=1`) 경로. 이번은 '다시 시작' 이었고 부팅 시각이 갱신됐다. (3) 덮개를 닫은 채로의 접속. (4) `sleep infinity` 가 유휴 종료를 막아 준다는 것 -- 작업 없이도 WSL 이 2일 넘게 켜져 있었으므로 필요 여부는 모른다 (재부팅 뒤 WSL 을 띄우는 주체로서는 필요).

- [x] 결과를 ADR 0010 의 '미검증' 과 troubleshooting 열린 항목에 반영
- [ ] (선택) 위 (2)(3): '종료' 후 전원 켜기, 덮개를 닫은 채 재부팅 없이 몇 분 둔 뒤 핸드폰 접속

## HTTPS 접속 시험 ([ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md))

NodePort 는 쓰지 않기로 했다 (공식 비권장, HTTP 로는 웹앱이 깨짐). 아래 순서로 HTTPS 경로를 시험한다.

- [x] 수동으로 띄운 `kubectl port-forward`(pid 58715, 127.0.0.1:8080) 종료: `kill 58715` -> 정리됨 (2026-10-26, 8080 은 서비스가 127.0.0.1 에서 잡고 있음)
- [x] `bash scripts/07-1-port-forward.sh` -> `bash scripts/verify/07-1-port-forward.sh`, 이 PC 에서 `http://localhost:8080` -> 통과 (2026-10-26)
- [x] Tailscale 관리 콘솔 DNS 페이지에서 MagicDNS 와 HTTPS Certificates 켜기 -> 켜져 있음 (serve 성공으로 확인)
- [x] `bash scripts/07-3-tailscale-serve.sh` -> `bash scripts/verify/07-3-tailscale-serve.sh` (리다이렉트가 `https://` 를 유지해야 한다) -> 통과: 리다이렉트가 https:// 유지 (2026-10-26)
- [x] 핸드폰에서 `https://<기기>.<tailnet>.ts.net` 접속, 로그인, **Notebook 생성** (이것이 핵심 시험) -> 통과 (2026-10-26): Notebook 생성 요청 200, 파드 2/2 Running (91초)
- [ ] 재부팅 후 `tailscale serve` 가 저절로 다시 공유되는지 (`verify/08-reboot.sh`)
- [ ] 쓰지 않는 NodePort 설정 정리: `kubectl --context kind-mlops -n istio-system delete networkpolicy allow-ingress-to-gateway-nodeport`, Service 는 `06` 재실행 또는 클러스터 재생성
- [ ] (정리) 쓰지 않는 `07-2-nodeport.sh`, `verify/07-2-nodeport.sh`, `kind-config.yaml` 의 30080 매핑을 삭제할지 결정

## 기능 시험

- [ ] 로그인 후 기능: Notebook 생성은 통과(HTTPS, 2026-10-26). 남은 것: 만든 Notebook 을 열어 코드 실행(웹소켓), Pipelines 실행, GPU Notebook
- [ ] Tailscale 관리 콘솔에서 쓰지 않는 offline 장치 7개 삭제 ([troubleshooting.md](troubleshooting.md) 5번)

## 재현성 검증 (재설치 마무리)

- [ ] `03` 의 `docker.sources` 저장소 등록을 `scripts/verify/03-docker.sh` 로 확인
- [ ] 삭제의 수정 경로(패키지 2개 purge, `docker0` 삭제)를 한 번 실행해 확인 ([troubleshooting.md](troubleshooting.md) 18번). `DRY_RUN=1` 로 먼저
- [ ] 이번 재설치 각 단계의 verify 출력을 [verify/README.md](../scripts/verify/README.md) 에 반영 (07 은 출력을 받지 못했다)
- [ ] 비밀번호 약함: `.env` 의 `KUBEFLOW_PASSWORD` 가 네 자리 숫자다. tailnet 밖으로 열기 전에 더 긴 값으로 바꾼다

## 문서

- [ ] `00`~`06`, ADR 0001~0008 을 ADR 0008 처럼 공식 문서와 다시 대조 (이번 세션은 0009, 0010 만 대조했다)

## 병합

- [ ] 위 검증이 끝나면 `dev` -> `main` PR. `main` 의 README 는 `dev` 를 가리키는 임시 링크와 안내 문구가 있으므로 충돌하면 `dev` 쪽 내용을 택한다
- [ ] `dev` 의 기존 커밋 48개는 작성자 이메일이 `dangim.co.kr` 이다 (히스토리를 다시 쓰지 않기로 했다)

## 이후

- [ ] IaC: Terraform 으로 tailscale ACL/authkey 와 클러스터 플랫폼 구성, ArgoCD 로 Kubeflow 배포 ([architecture.md](architecture.md))
