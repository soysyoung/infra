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
- **남겨 둔 NodePort 흔적**: `kind-config.yaml` 의 30080 매핑, `07-2` 스크립트들 (시험 기록). 게이트웨이 Service 는 ClusterIP 로 돌아왔다. NetworkPolicy `allow-ingress-to-gateway-nodeport` 는 없다 (`NotFound` 확인).
- **git**: `dev` 에 작업, `main` 은 README 한 파일(작성자 `soysyoung@gmail.com`). `dev` 의 기존 커밋 48개는 작성자 이메일이 `dangim.co.kr` 이다 (히스토리를 다시 쓰지 않기로 했다).

## 다음 할 일 (순서대로)

1. **기능 시험** (핸드폰, HTTPS 주소)
   - [x] `test01` 의 Connect 로 JupyterLab 열기, 셀 실행 (웹소켓이 `tailscale serve` 를 통과하는지) -> 통과 (2026-10-26): 핸드폰에서 JupyterLab 을 열고 셀을 실행했다. 게이트웨이 로그에서 커널 채널 웹소켓(HTTP 101)과 sessions/kernels API 200 확인 (test01 요청 290건)
   - [x] GPU Notebook -> 통과 (2026-10-26): GPU 워커에 taint `nvidia.com/gpu=present:NoSchedule` 이 있어 PodDefault [k8s/gpu-poddefault.yaml](../k8s/gpu-poddefault.yaml) 로 toleration 을 넣었다. Notebook `test02-gpu` 파드가 `mlops-worker` 에서 2/2 Running (`kubectl get pod -o wide`), 컨테이너 limits 에 `nvidia.com/gpu: 1`. Notebook 안에서의 `nvidia-smi` 출력은 보지 못했다 (미확인)
   - [x] Pipelines 실행 -> 통과 (2026-10-26): 컴포넌트 하나짜리 `hello-pipeline` 의 파드 3개(dag-driver, container-driver, impl)가 모두 Completed. 다중 사용자 모드라 Run 은 Experiment 를 먼저 만들고 그 안에서 만들어야 한다 (`Experiment id can not be empty in multi-user mode`). Run 상세 화면의 MLMD 오류(`Cannot find context ... system.PipelineRun`)는 Run 이 시작되기 전에 본 것으로, 이후 상태는 미확인. 노드의 출력값(`hello`)은 화면에서 보지 못했다
2. [x] **재부팅 후 `tailscale serve` 자동 재개** 확인 -> 통과 (2026-10-26): '다시 시작' 3분 뒤 `bash scripts/verify/08-reboot.sh` 가 docker, tailscaled active, 노드 4개 Ready, 노드 재시작 정책 `unless-stopped`, `127.0.0.1:8080` 과 tailnet HTTPS 주소의 로그인 리다이렉트(oauth2-proxy -> Dex) 정상으로 끝났다. `http://localhost:8080` 접속도 확인. 핸드폰에서 HTTPS 주소로 접속해 Notebook 에 연결됨(사용자 보고). 재부팅 뒤에도 `mlops-worker` 가 `nvidia.com/gpu: 1` 광고
3. **NodePort 잔재 정리 후 `06` 재실행**
   - [x] NetworkPolicy `allow-ingress-to-gateway-nodeport` 삭제 -> `get` 이 `NotFound` (2026-10-26)
   - [x] `bash scripts/06-kubeflow.sh` -> 통과 (2026-10-26): Service 가 ClusterIP 로 돌아왔고, `cookie-secret` 이 patch 됐고(managedFields 의 `kubectl-patch` 06:03:57 UTC, 파드 재시작과 일치), 새 비밀번호로 로그인되고 `http://localhost:8080` 이 열린다
   - [x] `07-2-nodeport.sh`, `verify/07-2-nodeport.sh`, `kind-config.yaml` 의 30080 매핑은 **삭제하지 않기로 했다** (2026-10-26, 시험 기록으로 남긴다. 스크립트는 이미 '사용하지 않음' 으로 표시했다). 매핑은 다음에 클러스터를 다시 만들 때 정리해도 된다
4. [x] **비밀번호 강화**: `.env` 의 `KUBEFLOW_PASSWORD` 를 바꾸고 `06` 을 다시 실행했다 (3번과 한 번에). 새 비밀번호로 로그인 확인.
5. **재현성 검증 마무리**
   - [x] `03` 의 `docker.sources` 저장소 등록 확인 (2026-10-26): `/etc/apt/sources.list.d/` 에 `docker.sources` 가 있고 `docker.list` 는 없다. 내용은 `download.docker.com/linux/ubuntu`, `Signed-By: /etc/apt/keyrings/docker.asc`. `verify/03-docker.sh` 는 `hello-world` 만 실행하므로 저장소 등록은 파일을 직접 읽어 확인했다
   - [ ] 삭제의 수정 경로(패키지 2개 purge, `docker0` 삭제) 실행 확인 ([troubleshooting.md](troubleshooting.md) 18번). `DRY_RUN=1` 먼저
   - [x] `03`~`06` verify 를 다시 실행해 모두 `==> OK` (2026-10-26), 차이점을 verify README 에 반영. `00-windows.ps1` 은 다시 실행하지 않았다
6. [x] Tailscale 관리 콘솔에서 쓰지 않는 offline 장치 7개 삭제 ([troubleshooting.md](troubleshooting.md) 5번) -> 2026-10-23 에 삭제함 (사용자 보고)
7. [x] 이전에 공식 문서 대조 없이 쓴 `00`~`06` 과 ADR 0001~0008 을 다시 대조 (2026-10-26) -> [ADR 0012](decisions/0012-official-doc-recheck.md). 틀린 곳 2개(ADR 0001 지원 종료일, `06` Dex 해시 주석)는 고쳤다. 남은 열린 항목:
   - [x] kind API 서버를 tailnet 주소에 여는 것은 kind 문서의 권고(loopback 유지)와 다르다 -> 다른 기기에서 `kubectl` 을 쓰므로 **유지하기로 했다** (2026-10-26). 근거와 위험은 [ADR 0012](decisions/0012-official-doc-recheck.md) 발견 1. 후속: Terraform 에서 tailnet ACL 로 6443 접근을 본인 기기로 제한
   - [ ] `02` 가 `tailscale up --ssh` 를 썼는데 현재 문서는 `tailscale set --ssh` 다. 스크립트를 문서 형식으로 고쳤다. 이 PC 에서 `sudo tailscale set --ssh` 를 실행하고 다른 기기에서 SSH 로 접속되는지는 아직 확인하지 못했다
   - [ ] 미확인: `05-1` 노드 재시작 정책의 Docker 문서 인용, `06` 의 kustomize 5.8.1 체크섬, ADR 0006 의 toolkit 1.20.1 WSL2 수정과 CUDA 12.8 요구
8. [ ] (선택) 재부팅의 남은 경우: 로그인 화면(비밀번호)이 있는 상태, 시작 메뉴 '종료' 후 전원 켜기(빠른 시작), 덮개를 닫은 채 접속
8-1. [ ] 외부 공유: tailnet 밖의 사람이 접속하려면 Tailscale Funnel 로 HTTPS 주소를 인터넷에 연다 (2026-10-26 결정: Funnel 사용). 공유용 계정은 `06-2-extra-user.sh` 로 만들었다. 켜기/끄기는 [scripts/07-4-tailscale-funnel.sh](../scripts/07-4-tailscale-funnel.sh). `on` 을 실행하고 접속을 확인했다 (2026-10-26, 사용자 보고. 출력은 받지 못했다). `off` 를 실행하자 연결이 끊겼다 (사용자 보고). `off` 뒤 `tailscale serve status` 가 `(tailnet only)` 로 `/` -> `http://127.0.0.1:8080` 을 보여 주고 `verify/07-3-tailscale-serve.sh` 가 `==> OK` 였다: 공개는 풀리고 tailnet 안의 HTTPS 는 유지된다. 모바일 데이터에서 실제로 막히는지는 직접 확인하지 못했다. 공유용 계정이 보는 범위: 실험과 Run 은 네임스페이스별로 분리되고, 파이프라인 정의는 모든 네임스페이스가 공유한다 ([공식 문서](https://www.kubeflow.org/docs/components/pipelines/operator-guides/multi-user/)). 주의: 관리자 계정(`user@example.com`)의 로그인 화면도 같은 주소로 공개된다
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
| 2026-10-26 | `06` 재실행 (ClusterIP 복귀, `cookie-secret` 교체, 새 비밀번호 로그인), GPU Notebook, Pipelines 실행 | 위 '다음 할 일' 1, 3, 4번 |
| 2026-10-26 | 재부팅 후 `tailscale serve` HTTPS 와 GPU 광고 유지, `03`~`06` verify 재실행 | `scripts/verify/08-reboot.sh`, [verify/README.md](../scripts/verify/README.md) |
| 2026-10-26 | `00`~`06` 과 ADR 0001~0008 공식 문서 재대조 | [ADR 0012](decisions/0012-official-doc-recheck.md) |
| 2026-10-26 | 두 번째 사용자(`06-2-extra-user.sh`): Dex 계정, Profile, 소유자 권한, 할당량(GPU 0). 새 계정으로 로그인해 `kubeflow-guest-example-com` 네임스페이스가 보였다 (사용자 보고). `verify/06-2-extra-user.sh` 가 `==> OK` 로 끝났고 할당량 `{"pods":"20","requests.nvidia.com/gpu":"0","requests.storage":"20Gi"}` 가 적용됐다. `06` 전체 재실행에서 끝의 `06-2` 호출은 아직 시험하지 않았다 | [scripts/README.md](../scripts/README.md), [Profile 문서](https://www.kubeflow.org/docs/components/central-dash/profiles/) |
| 2026-10-26 | Notebook 의 Python(`kfp.Client()`)으로 `hello-pipeline` 을 직접 제출해 YAML 업로드와 같은 결과를 확인. 이 클러스터에는 `access-ml-pipeline` PodDefault 가 없어서 [k8s/access-ml-pipeline-poddefault.yaml](../k8s/access-ml-pipeline-poddefault.yaml) 로 만들었다. 첫 Python Run 은 `container-impl` 파드 없이 끝났는데(캐시 적중으로 추정), `enable_caching=False` 로 다시 제출하자 dag-driver, container-driver, container-impl 파드 3개가 모두 `Completed` 였다 | [공식 안내](https://www.kubeflow.org/docs/components/pipelines/user-guides/core-functions/connect-api/) |
