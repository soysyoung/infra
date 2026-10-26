# TODO 와 새 세션 인수인계

앞으로 할 일과 새 세션에서 이어 하는 방법을 한곳에 둔다. 끝낸 일의 상세는 각 ADR 과 [verify/README.md](../scripts/verify/README.md), 막힌 곳은 [troubleshooting.md](troubleshooting.md).

## 새 세션에서 이어 하려면

**읽을 순서:** [README.md](../README.md) '상태' -> 이 문서 -> [troubleshooting.md](troubleshooting.md) '열린 항목' -> [ADR 0010](decisions/0010-reboot-recovery.md) (재부팅) -> [ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md) (접속 방식).

**작업 규칙 (사용자가 기대하는 것):**
- 시스템을 바꾸는 명령(WSL 설치, 관리자 PowerShell, `systemctl`, 클러스터 변경)은 **사용자가 직접 실행**한다. AI 는 스크립트를 쓰고 읽기 전용으로 진단한다. 파괴적 git 작업(force push 등)은 자동 권한 검사에서 막힐 수 있다.
- 새 사실은 **공식 문서나 이 PC 에서의 실측으로 확인**하고 출처를 적는다. 확인하지 못한 것은 '미검증' 이라고 쓴다. 구성을 만들기 전에 공식 접속/설치 안내를 먼저 읽는다 (NodePort 를 안내 없이 만들었다가 폐기했다, ADR 0011).
- 커밋: `dev` 브랜치, `<type>: <subject>`, **한 커밋 한 목적** (코드와 문서는 따로), 작성자는 `git -c user.name=soysyoung -c user.email=soysyoung@gmail.com`. push 는 사용자가 요청할 때만. `main` 은 PR (또는 사용자 승인 아래 fast-forward). 규칙은 [commit-convention.md](commit-convention.md).
- 문서 배치: 근거는 ADR, 사용법은 README, 실제 출력은 verify/teardown README, 막힌 곳은 troubleshooting. 저장소는 공개이므로 **tailnet 이름, 기기 모델, 사설 IP 는 쓰지 않는다** (`<기기>.<tailnet>.ts.net`).
- 도구 함정: `wsl.exe -- bash -c "..."` 로 넘긴 명령의 `$` 는 한 번 더 해석된다. 복잡한 명령은 스크립트를 표준입력으로 넘긴다 (`cat <<'EOF' | wsl.exe -- bash -s`). 문서를 파이썬으로 쓸 때 Windows 경로의 백슬래시가 이스케이프로 해석되어 파일이 깨진다 ([troubleshooting.md](troubleshooting.md) 19번). 쓴 뒤 제어문자와 탭을 검사한다.

## 현재 환경 (2026-10-26 기준)

- **Windows**: 예약 작업 `wsl-keepalive`(부팅 때 WSL 을 띄움, 로그온 없이), AC 절전과 최대 절전 끔, 덮개 닫기 '아무 것도 안 함'. Windows 에는 Tailscale 이 없다 (WSL 안에만 있다).
- **WSL**: `docker`, `tailscaled`, `kubeflow-port-forward`(`127.0.0.1:8080`) active. `tailscale serve` 가 HTTPS 로 `127.0.0.1:8080` 을 tailnet 에 연다 (tailnet only).
- **클러스터**: kind `mlops` 4노드 Ready (control-plane 1, GPU 워커 `mlops-worker`, CPU 워커 2), GPU 1개 광고, 비정상 파드 0. Kubeflow 26.03.1. 로그인 `user@example.com`, 비밀번호는 저장소 루트 `.env` 의 `KUBEFLOW_PASSWORD`. Notebook `test01` 이 Running.
- **접속**: 이 PC 는 `http://localhost:8080` (https 아님). 핸드폰 등 tailnet 기기는 `https://<기기>.<tailnet>.ts.net`. 이 PC 의 Windows 브라우저로는 `.ts.net` 주소가 해석되지 않는다.
- **치우지 않은 NodePort 잔재**: 게이트웨이 Service 가 NodePort, NetworkPolicy `allow-ingress-to-gateway-nodeport`, `kind-config.yaml` 의 30080 매핑, `07-2` 스크립트들.
- **이 클러스터에 아직 적용되지 않은 것**: `06` 의 `cookie-secret` 새로 만들기 (고친 뒤 `06` 을 다시 실행한 적이 없다. 다시 실행하면 로그인한 브라우저는 로그인 화면으로 돌아간다).
- **git**: `dev` 에 작업, `main` 은 README 한 파일(작성자 `soysyoung@gmail.com`). `dev` 의 기존 커밋 48개는 작성자 이메일이 `dangim.co.kr` 이다 (히스토리를 다시 쓰지 않기로 했다).

## 다음 할 일 (순서대로)

1. **기능 시험** (핸드폰, HTTPS 주소)
   - [x] `test01` 의 Connect 로 JupyterLab 열기, 셀 실행 (웹소켓이 `tailscale serve` 를 통과하는지) -> 통과 (2026-10-26): 핸드폰에서 JupyterLab 을 열고 셀을 실행했다. 게이트웨이 로그에서 커널 채널 웹소켓(HTTP 101)과 sessions/kernels API 200 확인 (test01 요청 290건)
   - [ ] GPU Notebook (GPU 워커의 taint 에 맞는 toleration 이 필요한지 확인)
   - [ ] Pipelines 실행
2. **재부팅 후 `tailscale serve` 자동 재개** 확인: '다시 시작' 후 `bash scripts/verify/08-reboot.sh` (07-3 검증을 함께 돈다)
3. **NodePort 잔재 정리 후 `06` 재실행**
   - [ ] `kubectl --context kind-mlops -n istio-system delete networkpolicy allow-ingress-to-gateway-nodeport`
   - [ ] `bash scripts/06-kubeflow.sh` -> Service 가 ClusterIP 로 돌아오는지(추정, 시험 전), `cookie-secret` 이 바뀌는지, 로그인이 다시 되는지
   - [ ] `07-2-nodeport.sh`, `verify/07-2-nodeport.sh`, `kind-config.yaml` 의 30080 매핑을 삭제할지 결정 (삭제하면 클러스터를 다시 만들어야 매핑이 사라진다)
4. **비밀번호 강화**: `.env` 의 `KUBEFLOW_PASSWORD` 가 네 자리 숫자다. 더 긴 값으로 바꾸고 `06` 을 다시 실행.
5. **재현성 검증 마무리**
   - [ ] `03` 의 `docker.sources` 저장소 등록을 `scripts/verify/03-docker.sh` 로 확인
   - [ ] 삭제의 수정 경로(패키지 2개 purge, `docker0` 삭제) 실행 확인 ([troubleshooting.md](troubleshooting.md) 18번). `DRY_RUN=1` 먼저
   - [ ] 이번 재설치의 `00`~`06` verify 출력을 verify README 에 반영
6. [ ] Tailscale 관리 콘솔에서 쓰지 않는 offline 장치 7개 삭제 ([troubleshooting.md](troubleshooting.md) 5번)
7. [ ] 이전에 공식 문서 대조 없이 쓴 `00`~`06` 과 ADR 0001~0008 을 ADR 0008 처럼 다시 대조 (0009~0011 은 대조했다)
8. [ ] (선택) 재부팅의 남은 경우: 로그인 화면(비밀번호)이 있는 상태, 시작 메뉴 '종료' 후 전원 켜기(빠른 시작), 덮개를 닫은 채 접속
9. [ ] 위가 끝나면 `dev` -> `main` PR (`main` 의 README 는 `dev` 를 가리키는 임시 링크가 있어 충돌하면 `dev` 쪽을 택한다)
10. [ ] IaC: Terraform 으로 tailscale ACL/authkey 와 클러스터 플랫폼 구성, ArgoCD 로 Kubeflow 배포 ([architecture.md](architecture.md))

## 끝낸 것 (근거)

| 날짜 | 내용 | 근거 |
|---|---|---|
| 2026-10-23 | 처음부터 재설치 `00`~`06`, kind 4노드, GPU 2차 관문, Kubeflow | [verify/README.md](../scripts/verify/README.md), [ADR 0006](decisions/0006-nvidia-wsl2-blackwell.md) |
| 2026-10-23 | `.env` 의 비밀번호를 dex 에 반영 (`06`), 새 비밀번호로 로그인 | [ADR 0005](decisions/0005-kubeflow-26.03.1.md) |
| 2026-10-26 | 재부팅 후 자동 복구 1회 통과 (예약 작업, 노드 `unless-stopped`, 전원 설정) | [ADR 0010](decisions/0010-reboot-recovery.md) |
| 2026-10-26 | 접속 방식 결정: NodePort 폐기, port-forward(localhost) + `tailscale serve` HTTPS. 서버 쪽 검증과 핸드폰의 Notebook 생성(200, 파드 91초) 통과 | [ADR 0009](decisions/0009-tailnet-exposure-port-forward-vs-nodeport.md), [ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md) |
| 2026-10-26 | 옛 세션 쿠키로 JWKS 401 이 나는 문제의 원인 확정, `06` 이 `cookie-secret` 을 새로 만들게 함 | [troubleshooting.md](troubleshooting.md) 24번 |
| 2026-10-26 | README 를 루트와 `scripts/` 로 분리, `main` 에 README 추가 | [README.md](../README.md) |
| 2026-10-26 | 핸드폰에서 Notebook 을 JupyterLab 으로 열어 코드 실행 (HTTPS + 웹소켓 통과) | 게이트웨이 로그, [ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md) |
