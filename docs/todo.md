# TODO 와 새 세션 인수인계

앞으로 할 일과 새 세션에서 이어 하는 방법을 한곳에 둔다. 끝낸 일의 상세는 각 ADR 과 [verify/README.md](../scripts/verify/README.md), 막힌 곳은 [troubleshooting.md](troubleshooting.md).

## 새 세션에서 이어 하려면

**읽을 순서:** [README.md](../README.md) '상태' -> 이 문서 -> [troubleshooting.md](troubleshooting.md) '열린 항목' -> [ADR 0010](decisions/0010-reboot-recovery.md) (재부팅) -> [ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md) (접속 방식).

**작업 규칙 (사용자가 기대하는 것):**
- 시스템을 바꾸는 명령(WSL 설치, 관리자 PowerShell, `systemctl`, 클러스터 변경)은 **사용자가 직접 실행**한다. AI 는 스크립트를 쓰고 읽기 전용으로 진단한다. 파괴적 git 작업(force push 등)은 자동 권한 검사에서 막힐 수 있다.
- 새 사실은 **공식 문서나 이 PC 에서의 실측으로 확인**하고 출처를 적는다. 확인하지 못한 것은 '미검증' 이라고 쓴다. 구성을 만들기 전에 공식 접속/설치 안내를 먼저 읽는다 (NodePort 를 안내 없이 만들었다가 폐기했다, ADR 0011).
- 커밋: `dev` 브랜치, `<type>: <subject>`, **한 커밋 한 목적** (코드와 문서는 따로), 작성자는 `git -c user.name=soysyoung -c user.email=soysyoung@gmail.com`. push 는 사용자가 요청할 때만. `main` 은 PR (또는 사용자 승인 아래 fast-forward). 규칙은 [commit-convention.md](commit-convention.md).
- 문서 배치: 근거는 ADR, 사용법은 README, 실제 출력은 verify/teardown README, 막힌 곳은 troubleshooting. 저장소는 공개이므로 **tailnet 이름, 기기 모델, 사설 IP 는 쓰지 않는다** (`<기기>.<tailnet>.ts.net`).
- 도구 함정: `wsl.exe -- bash -c "..."` 로 넘긴 명령의 `$` 는 한 번 더 해석된다. 복잡한 명령은 스크립트를 표준입력으로 넘긴다 (`cat <<'EOF' | wsl.exe -- bash -s`). 문서를 파이썬으로 쓸 때 Windows 경로의 백슬래시가 이스케이프로 해석되어 파일이 깨진다 ([troubleshooting.md](troubleshooting.md) 18번). 쓴 뒤 제어문자와 탭을 검사한다.

## 현재 환경 (2026-10-26 기준, WSL 줄은 2026-10-27, OpenSearch 와 접속 줄은 2026-10-30 갱신)

- **Windows**: 예약 작업 `wsl-keepalive`(부팅 때 WSL 을 띄움, 로그온 없이), AC 절전과 최대 절전 끔, 덮개 닫기 '아무 것도 안 함'. Windows 에는 Tailscale 이 없다 (WSL 안에만 있다).
- **WSL**: `docker`, `tailscaled`, `kubeflow-port-forward`(`127.0.0.1:8080`) active. `tailscale serve` 가 HTTPS 로 `127.0.0.1:8080` 을 tailnet 에 연다 (tailnet only). **`08-boot-resilience.sh` 이전 버전이 적용돼 있음 (2026-10-27)**: `docker.service` 시작 전 `tailscale wait --timeout=60s`, `kubeflow-port-forward` 가 전용 kubeconfig(`~/.kube/mlops-local.config`)로 API 서버를 컨트롤 플레인 컨테이너 IP(`172.18.0.4`)로 부름, `mlops-watchdog.timer` 가 1분마다 실행. 저장소의 `08` 은 이미 새 버전(감시 서비스만, API 서버는 `127.0.0.1`)으로 바뀌었고 이 PC 에는 재설치로 적용한다. 근거와 시험 결과는 [ADR 0010](decisions/0010-reboot-recovery.md) '사고 기록'. 컨트롤 플레인 IP 는 `/etc/mlops/cp-ip` 에 고정하고 클러스터를 다시 만들면 `08` 을 다시 실행한다. 일부러 `docker stop` 해 둔 클러스터는 감시가 다시 시작하니, 멈추려면 `sudo systemctl stop mlops-watchdog.timer` 부터 한다.
- **클러스터**: kind `mlops` 4노드 Ready (control-plane 1, GPU 워커 `mlops-worker`, CPU 워커 2), GPU 1장을 4개로 광고(time-slicing, 2026-10-28, [ADR 0013](decisions/0013-gpu-time-slicing.md)), OpenSearch 단일 노드 Running(네임스페이스 `opensearch`, [ADR 0014](decisions/0014-opensearch-single-node.md)), 프로필 ResourceQuota 적용(`06-4`, 기본 사용자 GPU 3 / 공유용 계정 GPU 0, 2026-10-28, [ADR 0015](decisions/0015-profile-resource-quota.md)), 비정상 파드 0 (2026-10-26 확인). Kubeflow 26.03.1. 로그인 `user@example.com`, 비밀번호는 저장소 루트 `.env` 의 `KUBEFLOW_PASSWORD`. Notebook `test01`, `test03`(CPU) 이 Running (`test02-gpu` 는 중지). 공유용 계정 `guest@example.com`(네임스페이스 `kubeflow-guest-example-com`, GPU 0)이 있고 비밀번호는 `.env` 의 `EXTRA_USER_PASSWORD`. Funnel 은 평소 꺼 둔다 (`07-4 off` 상태가 기본, 공유할 때만 `on`).
- **접속**: 이 PC 는 `http://localhost:8080` (https 아님). 핸드폰 등 tailnet 기기는 `https://<기기>.<tailnet>.ts.net`. 이 PC 의 Windows 브라우저로는 `.ts.net` 주소가 해석되지 않는다.
- **OpenSearch** (2026-10-30, `09-1`~`09-5`): 3.8.0 단일 노드(`09-1`), Dashboards(`09-2`, systemd 서비스 `opensearch-dashboards-port-forward` 가 `127.0.0.1:5601` 을 항상 열어 둔다, [ADR 0017](decisions/0017-opensearch-dashboards.md)), 게스트 계정 2개(`09-3`: guest-rw 는 `temp-*` 읽기·쓰기, guest-ro 는 `temp-*` 읽기 전용, 계정은 `.env` 의 `OPENSEARCH_GUEST_*`, [ADR 0018](decisions/0018-opensearch-guest-accounts.md)), tailnet 에서 `https://<기기>.<tailnet>.ts.net:8443` 으로 Dashboards(`09-4 private`, 평소 상태. `public` 은 외부에 보일 때만, 끝나면 `off`, [ADR 0019](decisions/0019-dashboards-tailscale-serve-funnel.md)), 모든 사용자 네임스페이스의 Notebook 에 guest-rw 를 환경변수로 주입(`09-5`, Notebook 을 만들 때 Configurations 에서 'OpenSearch guest-rw 접속 정보' 선택, [ADR 0020](decisions/0020-notebook-opensearch-guest-env.md)). admin 비밀번호는 `.env` 의 `OPENSEARCH_ADMIN_PASSWORD` 이고 이미 초기화된 클러스터에서는 `.env` 만 고쳐서는 바뀌지 않는다 (ADR 0017). **기기 이름을 바꾸면 옛 이름의 serve, funnel 설정이 남는다**: `sudo tailscale serve reset` 후 `07-3`, `09-4 private` 를 다시 실행 ([troubleshooting.md](troubleshooting.md) 30번).
- **남겨 둔 NodePort 흔적**: `07-2` 스크립트들 (시험 기록). `kind-config.yaml` 의 30080 매핑은 2026-10-27 에 제거했다 (이 PC 의 현재 클러스터에는 재설치 전까지 남아 있다). 게이트웨이 Service 는 ClusterIP 로 돌아왔다. NetworkPolicy `allow-ingress-to-gateway-nodeport` 는 없다 (`NotFound` 확인).
- **git**: `dev` 에 작업, `main` 은 README 한 파일(작성자 `soysyoung@gmail.com`). `dev` 의 기존 커밋 48개는 작성자 이메일이 `dangim.co.kr` 이다 (히스토리를 다시 쓰지 않기로 했다).

## 남은 일 (우선순위 순)

**진행 중**
1. [ ] **외부 공유 실제 시험** (사용자가 진행): `bash scripts/07-4-tailscale-funnel.sh on` -> 다른 사람이 `https://<기기>.<tailnet>.ts.net` 에 공유용 계정으로 접속 -> 끝나면 반드시 `off`. 결과(접속, 로그인, 자기 네임스페이스만 보이는지, 파이프라인 정의는 공유되는지)를 여기에 기록한다. 켜 둔 동안 관리자 로그인 화면도 공개된다. Let's Encrypt 속도 제한 때문에 켜고 끄기를 자주 반복하지 않는다

**재현성 증명: 전체 삭제 후 재설치** (2026-10-27 결정, 사용자가 진행. 합격 기준과 근거는 [ADR 0010](decisions/0010-reboot-recovery.md) '결정 변경')
18. [x] (2026-10-27 완료, 결과는 ADR 0010 '재설치 시험 결과') 삭제: WSL 안에서 `DRY_RUN=1 bash scripts/teardown/all.sh` 로 확인 후 `bash scripts/teardown/all.sh`, 이어서 PowerShell 에서 `scripts\teardown\00-windows-wsl.ps1`. 지워지는 것: Notebook 과 안의 데이터, 파이프라인 기록, 공유용 계정, Docker 이미지 전체. Tailscale 은 로그아웃과 제거까지 하므로 **장치가 새로 등록되고** 이름과 tailnet 주소가 바뀔 수 있다 (관리 콘솔의 옛 장치는 직접 삭제, `tailscale serve` HTTPS 인증서를 다시 받는다. Let's Encrypt 속도 제한이 있어 켜고 끄기를 반복하지 않는다). 삭제 확인은 [teardown/README.md](../scripts/teardown/README.md) '삭제 확인'
19. [x] (2026-10-27 완료. 개입이 필요했던 2곳은 고쳤고 재시험은 안 했다. `03`~`06` verify 출력은 받지 못함) 재설치: [scripts/README.md](../scripts/README.md) 의 순서대로 `00` 부터 `07-3`, 마지막에 `08`. 각 단계의 `verify/` 를 함께 실행. 이번에 바뀐 것: kind API 서버가 `127.0.0.1`, 30080 매핑 없음, `05-1` 이 Tailscale 에 의존하지 않음, `08` 은 감시 서비스만. 새 계정으로 `.env` 의 비밀번호가 그대로인지 확인
20. [x] (2026-10-27 통과: 재부팅 1회, `detach` 68초, `down` 143초) 재부팅 뒤 `bash scripts/verify/08-reboot.sh`, 그다음 `bash scripts/verify/08-boot-resilience.sh detach` 와 `down`. 결과와 걸린 시간, 실패한 항목을 ADR 0010 '결정 변경' 과 [troubleshooting.md](troubleshooting.md) 에 있는 그대로 기록한다

**부팅 복원력** (2026-10-27 사고, [ADR 0010](decisions/0010-reboot-recovery.md) '사고 기록'. 번호는 다른 문서가 참조하는 기존 번호를 지키려고 15번부터 이어 붙였다)
15. [x] **감시 서비스 복구 경로 시험** -> 통과 (2026-10-27): `bash scripts/verify/08-boot-resilience.sh detach` 와 `down` 을 사용자가 실행했고, 로그로 두 경우 모두 사람 조작 없이 복구됨을 확인했다 (`detach` 59초, `down` 2분 32초, 노드 4개 Ready, 8080 302). 상세와 한계는 [ADR 0010](decisions/0010-reboot-recovery.md) '대책 시험 결과'. 스크립트가 출력한 시간과 `verify/README.md` 의 실제 출력은 받지 못해 기록하지 않았다. 사고의 원인(경합) 자체를 재현하는 시험은 아니다
16. [ ] 남은 시험 (모두 미시험, 선택): 실행 중 전환 뒤 장시간 유지, 핸드폰의 `tailscale serve` 주소가 NIC 전환 뒤 돌아오는지. (`tailscale wait` 의 60초 시간 초과는 08 에서 `tailscale wait` 를 뺐으므로 해당 없음)
17. [ ] 선택: 원인 가설 확정(대기 없이 경합이 재현되는지), ADR 0010 의 10번(노드를 systemd 유닛으로 관리), 부팅 직후 `error: lost connection to pod` 가 반복되는 원인 확인

**확인만 하면 되는 것** (읽기 전용이거나 명령 한 번)
2. [ ] SSH: `sudo tailscale set --ssh` 실행 후 다른 기기에서 SSH 접속 확인 (`02` 는 이미 이 형식으로 고쳤다)
3. [ ] 다음에 `06` 을 전체 재실행할 때 끝의 `06-2` 호출이 정상인지 (이제 그 뒤의 `06-4` 호출과 기본 사용자 쿼터가 유지되는지도 함께 본다, [ADR 0015](decisions/0015-profile-resource-quota.md)) (아직 시험하지 않았다. `.env` 에 `EXTRA_USER_*` 가 있는 상태에서 `06` 이 `06-2` 를 다시 적용해야 한다)
4. [x] GPU Notebook 안에서 `nvidia-smi` 가 RTX 5080 을 보여 주는지 -> 통과 (2026-10-28): Notebook `test-gpu-01` 파드가 `mlops-worker` 에서 Ready 가 된 뒤 `kubectl exec ... nvidia-smi` 가 RTX 5080 (드라이버 592.27, CUDA 13.1, VRAM 16303MiB, 사용 0MiB)을 보여 줬다. 호스트(WSL)의 출력과 이름, 용량이 같다. 첫 실행은 이미지(`jupyter-pytorch-cuda-full`) 내려받기로 Ready 까지 약 5분. 이때 노드 광고는 `nvidia.com/gpu: 1` (time-slicing 적용 전, [ADR 0013](decisions/0013-gpu-time-slicing.md) 기준선). 연산 중 VRAM 사용은 보지 않았다

**공유용 계정을 더 믿고 쓰려면** (아직 하지 않았다)
5. [ ] 공유용 계정의 CPU, 메모리 할당량 (지금은 `quotas.env` 의 파드 20개, 스토리지 20Gi, GPU 0 만 제한한다, [ADR 0015](decisions/0015-profile-resource-quota.md). KFP 시스템 파드가 requests 없이 거부될 수 있어 일부러 뺐다. 시험 후 추가)
6. [ ] Dex 로그인 시도 횟수 제한이 있는지 확인 (인터넷에 열 때 비밀번호 대입 공격 대책)

**다음 클러스터 재생성 때**
7. [x] 삭제의 수정 경로 실행 확인 -> 부분 통과 (2026-10-27 실제 삭제): 패키지 2개 purge 는 출력으로 확인. `docker0` 삭제는 출력이 없고 이어서 배포판을 지워 확인하지 못했다 ([troubleshooting.md](troubleshooting.md) 17번)
8. [x] `kind-config.yaml` 의 30080 매핑 제거와 `apiServerAddress` 를 `127.0.0.1` 로 변경 -> 저장소에 반영 (2026-10-27, [ADR 0010](decisions/0010-reboot-recovery.md) '결정 변경'). 클러스터에는 위 18~19번 재설치로 적용된다. `07-2` 스크립트는 시험 기록으로 남기고 새 클러스터에서는 안내하고 멈춘다
9. [ ] 두 번째 사용자 삭제 경로(`kubectl delete profile <이름>`, `.env` 정리, `06` 재실행) 시험

**선택**
10. [ ] 재부팅의 남은 경우: 로그인 화면(비밀번호)이 있는 상태, 시작 메뉴 '종료' 후 전원 켜기(빠른 시작), 덮개를 닫은 채 접속
11. [ ] [ADR 0012](decisions/0012-official-doc-recheck.md) 의 미확인 항목: `05-1` 노드 재시작 정책의 Docker 문서 인용, `06` 의 kustomize 5.8.1 체크섬, ADR 0006 의 toolkit 1.20.1 WSL2 수정과 CUDA 12.8 요구
12. [ ] `scripts/verify/00-windows.ps1` 다시 실행 (이번에는 `03`~`06` 만 돌렸다)
21. [x] 워크로드용 저장소 (2026-10-28 결정 변경): 파이프라인 정의, 학습·추론 코드, 노트북 예제, 실험 기록은 거기에 두고 이 저장소는 플랫폼만 다룬다. **프로젝트마다 단독 저장소**로 한다 (처음에 쓴 "저장소 하나에 프로젝트별 폴더"는 폐기). 첫 프로젝트는 [fashion-recsys-mlops](https://github.com/soysyoung/fashion-recsys-mlops), [README.md](../README.md) '범위' 에 링크했다. 이 저장소가 제공하는 것(접속 주소, GPU PodDefault [k8s/gpu-poddefault.yaml](../k8s/gpu-poddefault.yaml), GPU time-slicing, OpenSearch, 네임스페이스)은 문서로만 참조하게 한다
22. [x] 프로필 ResourceQuota ([ADR 0015](decisions/0015-profile-resource-quota.md)) -> 통과 (2026-10-28, 사용자 실행). 첫 `06-4`: 기본 사용자 Profile `patched`, guest `patched (no change)`, `verify/06-4` `==> OK`. 기본 사용자 `kf-resource-quota` 가 11초 만에 생겨 `requests.nvidia.com/gpu: 1/3` (1개 사용 중), guest 는 `pods 0/20, gpu 0/0, storage 0/20Gi` 그대로. 17분 뒤 재실행은 둘 다 `no change` 로 멱등. `verify/06-4-quotas.sh roundtrip` 도 통과 (같은 날): A 기존 쿼터 객체가 갱신되고 비운 키(pods)가 사라짐, B GPU 0 인 guest 네임스페이스에 GPU 파드를 서버 dry-run 으로 보내면 `exceeded quota` 로 거부됨, C 새 `06-2` 가 guest 쿼터를 지우고(`- - -`) `06-4` 가 되살림. 두 번째 `roundtrip` 도 통과: 기본 사용자 네임스페이스의 한도 초과(GPU 4개 > 3)도 `exceeded quota` 로 거부, 이후 `06-2` 를 두 번 더 실행해도 guest 쿼터는 그대로. 미시험: `06` 전체 재실행(3번, 06 은 server-side apply 라 06-4 의 필드가 남을 것으로 추정만 한다). GPU 배분 3/0/예약 1 은 제안값 그대로 적용 중. CPU, 메모리 쿼터는 5번과 함께 시험 후 (메모리 합계는 [ADR 0014](decisions/0014-opensearch-single-node.md) '메모리 예산' 의 수치를 근거로)
23. [ ] GPU 동시 실행 시험: 파드 둘 이상이 한 GPU 를 쓸 때 각자의 VRAM 점유와 속도 ([ADR 0013](decisions/0013-gpu-time-slicing.md) 미검증). 워크로드 저장소 README 에 "VRAM 은 코드에서 상한을 건다"는 안내를 남긴다
24. [ ] OpenSearch 에 실제 벡터(약 10.5만 x 384차원)를 넣은 뒤의 메모리 확인, 파드 재시작과 WSL 재부팅 뒤 색인 보존, 전체 재설치 경로(`05-4`, `09` 포함)에서의 동작
25. [ ] `scripts/06-3-poddefaults.sh` 와 `verify/06-3-poddefaults.sh` 실행 확인 (2026-10-28 작성, 미시험). 지금 클러스터에는 PodDefault 두 개가 이미 있어 `unchanged` 가 나와야 하고, 재설치 경로에서 처음부터 만들어지는지는 24번의 전체 재설치 때 확인한다
26. [ ] OpenSearch GPU 원격 인덱스 빌드 go/no-go 실험 (조사 기록은 [ADR 0016](decisions/0016-opensearch-remote-gpu-index-build.md), 근거가 `latest` 문서라 **OpenSearch 3.8.0 지원 여부는 미검증**). 켜기 전에 확인: 3.8.0 지원 여부, 빌더 소스에서 S3 커스텀 엔드포인트(MinIO) 지원 여부, 빌더 이미지 digest 고정, 빌드 중 `nvidia-smi` 로 VRAM 측정. 안 되면 CPU 빌드로 둔다. GPU 슬라이스 1개를 미배정으로 남겨 둔다 (22번 배분). 워크로드 쪽에는 "GPU 빌드를 쓰려면 faiss hnsw" 를 문서로만 알린다

**OpenSearch Dashboards 와 게스트 계정** (2026-10-30 적용, 남은 시험)
27. [x] guest-ro 의 Dashboards 화면 확인 (2026-10-30, [ADR 0018](decisions/0018-opensearch-guest-accounts.md)): `temp-*` 검색(Dev Tools GET) 200, 인덱스 패턴은 guest 가 못 만들어 admin 이 Global tenant 에서 만들었고(admin 은 `all_access` 로 tenant 쓰기 권한이 있다) guest-ro 가 API 로 읽는 것을 확인. 사용자가 guest-ro 로 화면을 확인했다고 보고했다 (Discover 결과의 내용은 받지 못했다). guest-rw 의 Dashboards 화면 제한은 확인하지 않았다
28. [ ] 일부 완료 (2026-10-30): `09-4 public` 으로 공개 주소에 접속해 guest-ro 로그인, tenant 를 Global 로 고르면 Discover 에 `temp-*` 가 보인다 (사용자 보고, [ADR 0019](decisions/0019-dashboards-tailscale-serve-funnel.md)). 남은 것: 그 접속이 Tailscale 을 끈 기기였는지, `off` 뒤 외부에서 끊기는지, `serve status` 에 Funnel 표시가 없는지. (고친 `verify/09-4` 재실행은 통과했다: `443(Kubeflow) 항목도 그대로 있음`)
29. [x] 고친 `verify/09-5` 재실행 통과 (2026-10-30): 서버 dry-run 이 환경변수 3개 주입을 보여 주고 Notebook 접속 200 (두 네임스페이스). 이전 실행은 `apply` 의 `generateName` 제약으로 dry-run 이 건너뛰어졌다
30. [ ] 일부 완료 (2026-10-30): Dashboards 메모리 실측 약 376MiB / 한도 1Gi, 재시작 0 (가벼운 사용 기준, [ADR 0017](decisions/0017-opensearch-dashboards.md)). `.env` 의 admin 비밀번호 길이 18 (12 이상 조건 충족). `teardown/09-1` 로 OpenSearch 만 지우고 `09-1`~`09-5` 를 처음부터 다시 실행해 모든 `verify` 가 `==> OK` (2026-10-30, [teardown/README.md](../scripts/teardown/README.md)). 남은 것: 새 클러스터(Helm, Istio 가 처음 설치되는 환경)에서의 `09-1`~`09-5` 와 `all.sh` 전체 삭제 (다음 전체 재설치 때), 무거운 사용에서의 메모리

**큰 일**
13. [ ] `dev` -> `main` PR (보류 중. `main` 의 README 는 `dev` 를 가리키는 임시 링크가 있어 충돌하면 `dev` 쪽을 택한다)
14. [ ] IaC (Terraform, 나중에): Funnel 사용자를 제한 (6443 은 `127.0.0.1` 로 바뀌어 ACL 제한이 필요 없다, ADR 0010), authkey, 클러스터 플랫폼 구성, ArgoCD 로 Kubeflow 배포 ([architecture.md](architecture.md), [ADR 0012](decisions/0012-official-doc-recheck.md) 발견 1)

## 2026-10-26 에 끝낸 일의 상세

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
   - [x] `03`~`06` verify 를 다시 실행해 모두 `==> OK` (2026-10-26), 차이점을 verify README 에 반영. `00-windows.ps1` 은 다시 실행하지 않았다
6. [x] Tailscale 관리 콘솔에서 쓰지 않는 offline 장치 7개 삭제 -> 2026-10-23 에 삭제함 (사용자 보고)
7. [x] 이전에 공식 문서 대조 없이 쓴 `00`~`06` 과 ADR 0001~0008 을 다시 대조 (2026-10-26) -> [ADR 0012](decisions/0012-official-doc-recheck.md). 틀린 곳 2개(ADR 0001 지원 종료일, `06` Dex 해시 주석)는 고쳤다. 남은 열린 항목:
   - [x] kind API 서버를 tailnet 주소에 여는 것은 kind 문서의 권고(loopback 유지)와 다르다 -> 다른 기기에서 `kubectl` 을 쓰므로 **유지하기로 했다** (2026-10-26. **2026-10-27 에 `127.0.0.1` 로 바꾸기로 결정을 바꿨다**, ADR 0010). 근거와 위험은 [ADR 0012](decisions/0012-official-doc-recheck.md) 발견 1. 후속: Terraform 에서 tailnet ACL 로 6443 접근을 본인 기기로 제한
   - `02` 의 `tailscale up --ssh` 는 현재 문서 형식(`tailscale set --ssh`)으로 고쳤다. 실행 확인은 위 '남은 일' 2번
8-1. [x] 외부 공유 구성과 켜기/끄기 시험 (실제 다른 사용자 공유 시험은 위 '남은 일' 1번): tailnet 밖의 사람이 접속하려면 Tailscale Funnel 로 HTTPS 주소를 인터넷에 연다 (2026-10-26 결정: Funnel 사용). 공유용 계정은 `06-2-extra-user.sh` 로 만들었다. 켜기/끄기는 [scripts/07-4-tailscale-funnel.sh](../scripts/07-4-tailscale-funnel.sh). `on` 을 실행하고 접속을 확인했다 (2026-10-26, 사용자 보고. 출력은 받지 못했다). `off` 를 실행하자 연결이 끊겼다 (사용자 보고). `off` 뒤 `tailscale serve status` 가 `(tailnet only)` 로 `/` -> `http://127.0.0.1:8080` 을 보여 주고 `verify/07-3-tailscale-serve.sh` 가 `==> OK` 였다: 공개는 풀리고 tailnet 안의 HTTPS 는 유지된다. tailnet 밖(핸드폰의 Tailscale 끔)에서는 `ERR_CONNECTION_CLOSED` 로 접속되지 않는다 (사용자 보고). 공유용 계정이 보는 범위: 실험과 Run 은 네임스페이스별로 분리되고, 파이프라인 정의는 모든 네임스페이스가 공유한다 ([공식 문서](https://www.kubeflow.org/docs/components/pipelines/operator-guides/multi-user/)). 주의: 관리자 계정(`user@example.com`)의 로그인 화면도 같은 주소로 공개된다

## 끝낸 것 (근거)

| 날짜 | 내용 | 근거 |
|---|---|---|
| 2026-10-23 | 처음부터 재설치 `00`~`06`, kind 4노드, GPU 2차 관문, Kubeflow | [verify/README.md](../scripts/verify/README.md), [ADR 0006](decisions/0006-nvidia-wsl2-blackwell.md) |
| 2026-10-23 | `.env` 의 비밀번호를 dex 에 반영 (`06`), 새 비밀번호로 로그인 | [ADR 0005](decisions/0005-kubeflow-26.03.1.md) |
| 2026-10-26 | 재부팅 후 자동 복구 1회 통과 (예약 작업, 노드 `unless-stopped`, 전원 설정) | [ADR 0010](decisions/0010-reboot-recovery.md) |
| 2026-10-26 | 접속 방식 결정: NodePort 폐기, port-forward(localhost) + `tailscale serve` HTTPS. 서버 쪽 검증과 핸드폰의 Notebook 생성(200, 파드 91초) 통과 | [ADR 0009](decisions/0009-tailnet-exposure-port-forward-vs-nodeport.md), [ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md) |
| 2026-10-26 | 옛 세션 쿠키로 JWKS 401 이 나는 문제의 원인 확정, `06` 이 `cookie-secret` 을 새로 만들게 함 | [troubleshooting.md](troubleshooting.md) 23번 |
| 2026-10-26 | README 를 루트와 `scripts/` 로 분리, `main` 에 README 추가 | [README.md](../README.md) |
| 2026-10-26 | 핸드폰에서 Notebook 을 JupyterLab 으로 열어 코드 실행 (HTTPS + 웹소켓 통과) | 게이트웨이 로그, [ADR 0011](decisions/0011-no-nodeport-https-via-tailscale-serve.md) |
| 2026-10-26 | `06` 재실행 (ClusterIP 복귀, `cookie-secret` 교체, 새 비밀번호 로그인), GPU Notebook, Pipelines 실행 | 위 '다음 할 일' 1, 3, 4번 |
| 2026-10-26 | 재부팅 후 `tailscale serve` HTTPS 와 GPU 광고 유지, `03`~`06` verify 재실행 | `scripts/verify/08-reboot.sh`, [verify/README.md](../scripts/verify/README.md) |
| 2026-10-26 | `00`~`06` 과 ADR 0001~0008 공식 문서 재대조 | [ADR 0012](decisions/0012-official-doc-recheck.md) |
| 2026-10-26 | 두 번째 사용자(`06-2-extra-user.sh`): Dex 계정, Profile, 소유자 권한, 할당량(GPU 0). 새 계정으로 로그인해 `kubeflow-guest-example-com` 네임스페이스가 보였다 (사용자 보고). `verify/06-2-extra-user.sh` 가 `==> OK` 로 끝났고 할당량 `{"pods":"20","requests.nvidia.com/gpu":"0","requests.storage":"20Gi"}` 가 적용됐다. `06` 전체 재실행에서 끝의 `06-2` 호출은 아직 시험하지 않았다 | [scripts/README.md](../scripts/README.md), [Profile 문서](https://www.kubeflow.org/docs/components/central-dash/profiles/) |
| 2026-10-26 | Notebook 의 Python(`kfp.Client()`)으로 `hello-pipeline` 을 직접 제출해 YAML 업로드와 같은 결과를 확인. 이 클러스터에는 `access-ml-pipeline` PodDefault 가 없어서 [k8s/access-ml-pipeline-poddefault.yaml](../k8s/access-ml-pipeline-poddefault.yaml) 로 만들었다. 첫 Python Run 은 `container-impl` 파드 없이 끝났는데(캐시 적중으로 추정), `enable_caching=False` 로 다시 제출하자 dag-driver, container-driver, container-impl 파드 3개가 모두 `Completed` 였다 | [공식 안내](https://www.kubeflow.org/docs/components/pipelines/user-guides/core-functions/connect-api/) |
| 2026-10-28 | GPU 1장을 4개로 광고(time-slicing). 노드 광고 4, 스모크 파드 통과, 재시작한 Notebook 의 `nvidia-smi` 가 같은 GPU. 동시 실행은 미시험 (위 23번) | [ADR 0013](decisions/0013-gpu-time-slicing.md) |
| 2026-10-28 | OpenSearch 3.8.0 단일 노드 (Helm 4.2.4). `verify/09` 통과, 클러스터 green, `opensearch-knn` 있음, 파드 4Gi, WSL 사용 9.0GB 로 `.wslconfig` 24GB 유지 | [ADR 0014](decisions/0014-opensearch-single-node.md) |
| 2026-10-28 | 프로필 ResourceQuota (`06-4`, `quotas.env`): 기본 사용자 GPU 3, 공유용 계정 파드 20 / 20Gi / GPU 0. 갱신, 비운 키 제거, 한도 초과 거부(서버 dry-run), `06-2` 재실행 뒤 복원을 `roundtrip` 으로 확인. `06` 전체 재실행은 미시험 | [ADR 0015](decisions/0015-profile-resource-quota.md), [verify/README.md](../scripts/verify/README.md) |
| 2026-10-30 | OpenSearch Dashboards(`09-2`), 게스트 계정 2개와 권한 분리(`09-3`), Dashboards 의 tailnet/Funnel 노출(`09-4`), Notebook 용 guest-rw 환경변수 주입(`09-5`). `verify/09-2`, `09-3`(12개 항목), `09-4` 통과, Notebook 에서 `temp-*` 쓰기 201 과 범위 밖 403 확인. 기기 이름 변경 뒤 옛 serve 설정이 남아 `serve reset` 으로 정리 | [ADR 0017](decisions/0017-opensearch-dashboards.md)~[0020](decisions/0020-notebook-opensearch-guest-env.md), [verify/README.md](../scripts/verify/README.md), [troubleshooting.md](troubleshooting.md) 30번 |
| 2026-10-27 | 컨트롤 플레인이 kind 네트워크에서 떨어져 8080 이 막힌 사고를 복구하고 `08-boot-resilience.sh` 를 적용. 대기(`tailscale wait`)가 `tailscale0` 준비를 기다림, 오프라인 부팅에서도 8080 이 NIC 없이 열림, 실행 중 전환 2건에서 port-forward 가 죽지 않음을 확인. 같은 날 감시 서비스 복구 경로(`detach`, `down`)도 통과. 60초 시간 초과 등은 미시험 (위 16번) | [ADR 0010](decisions/0010-reboot-recovery.md) '사고 기록', [troubleshooting.md](troubleshooting.md) 27번 |
