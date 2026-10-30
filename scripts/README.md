# 설치 스크립트

노트북(Windows 11 + WSL2 + RTX 5080)에 Tailscale, Docker, kind, Kubeflow 를 설치한다. 모든 명령은 **저장소 루트**(`infra`)에서 실행한다.

## 사전 요구

- Windows 11 22H2 이상 (build 22621+), 관리자 권한
- NVIDIA GPU 와 **Windows 쪽** NVIDIA 드라이버 (WSL 안에는 드라이버를 설치하지 않는다). 검증한 환경: RTX 5080 Laptop, 드라이버 592.27
- RAM 32GB 권장 (WSL 에 24GB 할당, Kubeflow 는 16GB 이상 권장), 디스크 여유 100GB 이상
- Tailscale 계정 (원격 접속용)
- 이 PC 가 조건을 갖췄는지는 `scripts\verify\00-windows.ps1` 로 확인한다

## 설정 파일

| 파일 | 내용 |
|---|---|
| [versions.env](../versions.env) | 모든 버전의 단일 출처 (kind, 노드 이미지, Docker, NVIDIA toolkit, Kubeflow, kustomize ...). 스크립트가 읽는다 |
| [cluster.env](../cluster.env) | 클러스터 토폴로지 (`CPU_WORKERS`, inotify 한도). 바꾸면 클러스터를 다시 만든다 |
| [windows/wslconfig.example](../windows/wslconfig.example) | `.wslconfig` 예시 (메모리 24GB, mirrored 네트워킹). `00` 이 복사한다 |

## 실행 순서

Windows 관리자 PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\00-windows-wsl.ps1   # 재부팅 안내가 나오면 재부팅 후 다시 실행
```

WSL Ubuntu 24.04 안에서:

```bash
bash scripts/01-wsl-systemd.sh        # 끝나면 PowerShell 에서 wsl --shutdown
bash scripts/02-tailscale.sh          # 로그인 URL 이 나오면 브라우저로 인증
bash scripts/03-docker.sh             # DOCKER_VERSION 이 비어 있으면 목록을 보여주고 멈춘다
bash scripts/04-nvidia-toolkit.sh
bash scripts/verify/04-gpu.sh         # GPU 1차 관문 (Docker 컨테이너)
bash scripts/05-1-kind-cluster.sh     # kind 4노드 (control-plane 1, GPU 1, CPU 2)
bash scripts/05-2-gpu-node.sh         # GPU 노드 컨테이너에 toolkit, containerd 설정
bash scripts/05-3-device-plugin.sh    # device plugin (GPU 노드에만)
bash scripts/verify/05-3-device-plugin.sh   # GPU 2차 관문 (GPU 노드의 파드)
bash scripts/05-4-helm.sh             # (선택) helm 설치 (09 OpenSearch 용, 체크섬 검증)
bash scripts/verify/05-4-helm.sh
bash scripts/06-kubeflow.sh           # Pipelines, Notebooks, KServe (첫 설치는 이미지를 많이 받아 오래 걸린다)
bash scripts/verify/06-kubeflow.sh
bash scripts/06-3-poddefaults.sh      # PodDefault 2개: gpu-toleration(GPU Notebook 필수), access-ml-pipeline
bash scripts/verify/06-3-poddefaults.sh
bash scripts/06-2-extra-user.sh       # (선택) 두 번째 사용자. .env 의 EXTRA_USER_EMAIL, EXTRA_USER_PASSWORD 가 있을 때만 동작
bash scripts/verify/06-2-extra-user.sh
bash scripts/06-4-quotas.sh           # 프로필 네임스페이스 ResourceQuota (값은 quotas.env, 06-2 다음에 실행). ADR 0015
bash scripts/verify/06-4-quotas.sh
# 접속 (ADR 0011). 이 PC 는 07-1 만으로 충분하고, 다른 기기(핸드폰 등)는 07-3 까지 한다
bash scripts/07-1-port-forward.sh     # systemd 로 감싼 kubectl port-forward -> http://localhost:8080
bash scripts/verify/07-1-port-forward.sh
bash scripts/07-3-tailscale-serve.sh  # tailscale serve 로 HTTPS -> https://<기기>.<tailnet>.ts.net (관리 콘솔에서 MagicDNS, HTTPS 인증서를 먼저 켠다)
bash scripts/verify/07-3-tailscale-serve.sh
bash scripts/07-4-tailscale-funnel.sh on|off|status   # (선택) tailnet 밖의 사람에게 인터넷으로 공개/해제. 공유할 때만 on 하고 끝나면 off
bash scripts/08-boot-resilience.sh    # 컨트롤 플레인이 kind 네트워크에서 떨어지거나 멈추면 스스로 복구하고, 8080 이 멈추면 port-forward 를 재시작하는 1분 감시 서비스. ADR 0010
bash scripts/verify/08-boot-resilience.sh detach   # (선택, 클러스터가 2~4분 끊긴다) 일부러 장애를 만들어 감시가 복구하는지 시험. down 도 있다
bash scripts/09-1-opensearch.sh       # (선택) OpenSearch 단일 노드 + k-NN (Helm). 관리자 계정(admin)과 비밀번호를 .env 의 OPENSEARCH_ADMIN_USER, OPENSEARCH_ADMIN_PASSWORD 에 만든다. ADR 0014
bash scripts/verify/09-1-opensearch.sh
bash scripts/09-2-opensearch-dashboards.sh   # (선택) 브라우저용 웹 UI. 같은 .env 비밀번호로 로그인. systemd 서비스가 127.0.0.1:5601 port-forward 를 계속 살려 둔다(터미널 불필요). ADR 0017
bash scripts/verify/09-2-opensearch-dashboards.sh
bash scripts/09-3-opensearch-guests.sh   # (선택) 게스트 계정 2개: guest-rw(temp-* 에 쓰기·읽기), guest-ro(읽기 전용). 이름과 비밀번호는 .env 의 OPENSEARCH_GUEST_*. ADR 0018
bash scripts/verify/09-3-opensearch-guests.sh
bash scripts/09-4-dashboards-tailscale.sh private   # (선택) Dashboards 를 tailnet 에서 https://<기기>.<tailnet>.ts.net:8443 으로 연다. public 은 인터넷 공개(필요할 때만), off 로 닫는다. ADR 0019
bash scripts/verify/09-4-dashboards-tailscale.sh
bash scripts/09-5-opensearch-notebook-access.sh   # (선택) Notebook 에 guest-rw 접속 정보를 환경변수로 주입 (Secret + PodDefault, 모든 사용자 네임스페이스). Notebook 만들 때 Configurations 에서 고른다. ADR 0020
bash scripts/verify/09-5-opensearch-notebook-access.sh
bash scripts/10-1-postgres.sh        # (선택) PostgreSQL 단일 인스턴스 (CloudNativePG 연산자 Helm + Cluster). 앱 계정 app 의 비밀번호는 .env 의 POSTGRES_APP_PASSWORD (공식 기본값과 다르다, 아래 'PostgreSQL (10-1)'), 서비스 postgres-rw.postgres.svc:5432. ADR 0021
bash scripts/verify/10-1-postgres.sh
bash scripts/10-2-postgres-notebook-access.sh   # (선택) Notebook 에 PostgreSQL 접속 정보를 환경변수로 주입. 기본 사용자 네임스페이스에는 소유자 app(모든 권한), 공유용(guest) 네임스페이스에는 데이터 읽기/쓰기 전용 계정 notebook_rw(DDL 불가)의 Secret + PodDefault 를 둔다. .env 의 POSTGRES_APP_PASSWORD, POSTGRES_NOTEBOOK_PASSWORD. ADR 0022
bash scripts/verify/10-2-postgres-notebook-access.sh
```

단계마다 짝이 되는 검증이 `scripts/verify/` 에 있다. 사용법과 실제 출력은 [verify/README.md](verify/README.md).

## PostgreSQL (10-1)

CloudNativePG 연산자를 Helm 으로 설치하고 `Cluster` 하나(단일 인스턴스, DB `app`)를 만든다. 접속은 클러스터 안에서 `postgres-rw.postgres.svc:5432`, 이 PC 에서는 `kubectl -n postgres port-forward svc/postgres-rw 5432:5432`. 근거와 미검증 항목은 [ADR 0021](../docs/decisions/0021-postgres-cloudnativepg.md).

**Notebook 에서 쓰기 (10-2).** `10-2-postgres-notebook-access.sh` 를 실행한 뒤 Notebook 을 만들 때 Configurations 에서 'PostgreSQL 접속 정보' 를 고르면 `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSFILE` 이 들어가고 비밀번호는 환경변수가 아니라 password file 로 들어간다 (PostgreSQL 공식 문서가 `PGPASSWORD` 를 권하지 않는다. 이유와 구조는 ADR 0022 '비밀번호 전달'). 들어가는 계정은 네임스페이스마다 다르다: 기본 사용자 네임스페이스는 소유자 `app`(테이블 생성과 삭제를 포함한 모든 권한), 공유용(guest) 네임스페이스는 `notebook_rw`(`app` 데이터베이스의 모든 테이블을 읽고 쓰지만 테이블을 만들거나 지우지는 못한다). `PGPASSWORD` 구성으로 실행해 user, guest Notebook 모두에서 접속까지 확인했고, password file 로 바꾼 구성은 DB 쪽 verify, dry-run, Notebook 파드의 password file 생성(0600, 읽기 가능)까지 확인했고 그 파일로 로그인되는지는 아직 확인하지 못했다. 기본 Notebook 이미지에는 `psycopg2` 가 없어 Notebook 마다 설치해야 한다: 셀에서 `pip install psycopg2-binary` 를 하거나 `pip install --user psycopg2-binary` 를 한다 (`--user` 는 PVC 인 `/home/jovyan` 에 설치돼 Notebook 이 재생성돼도 남을 가능성이 있으나 시험하지 않았다. psycopg2 공식 문서는 `-binary` 를 입문용으로 소개하고 운영에는 소스 배포를 권한다). 이미 떠 있던 Notebook 은 재시작이 아니라 라벨이 없어서 안 들어간다: Notebook 을 새로 만들 때 고른다 ([ADR 0022](../docs/decisions/0022-notebook-postgres-access.md)).

**공식 기본값과 다르게 설정한 것: 앱 계정 비밀번호.** 공식 기본값은 연산자가 비밀번호를 무작위로 만들어 Secret 에 두는 것이다. 이 저장소는 대신 `.env` 의 `POSTGRES_APP_PASSWORD` 로 Secret `postgres-app-auth` 를 만들어 쓴다 (직접 만든 비밀번호를 쓰는 방법은 [공식 문서](https://cloudnative-pg.io/docs/1.30/bootstrap/)에 있으나 권장 기본값은 아니다). 이유는 전체 삭제 후 재설치로 재현성을 증명하는 이 저장소에서, 기본값은 재설치할 때마다 비밀번호가 바뀌어 그 값을 쓰는 곳을 매번 고쳐야 하기 때문이다. `.env` 에 두면 재설치해도 같다. 대가는 비밀번호가 `.env` 와 Secret 두 곳에 있고, DB 를 처음 만들 때만 쓰이므로 `.env` 만 고쳐서는 바뀌지 않는다는 점이다.

```bash
grep '^POSTGRES_APP_' .env    # 계정 이름과 비밀번호
```

## Kubeflow 접속

```bash
bash scripts/07-1-port-forward.sh   # 상시 서비스로 띄운다 -> http://localhost:8080 (수동으로 kubectl port-forward 를 띄우면 07-1 과 포트가 겹친다)
```

로그인은 `user@example.com` 이고, 비밀번호는 저장소 루트의 `.env` (git 제외) 의 `KUBEFLOW_PASSWORD` 다. 바꾼 뒤 `bash scripts/06-kubeflow.sh` 를 다시 실행하면 dex 에 반영된다. `.env` 가 없으면 공개된 기본값 `12341234` 이므로 바꾸기 전에는 외부에 노출하지 않는다 ([ADR 0005](../docs/decisions/0005-kubeflow-26.03.1.md)). 파드는 `kubectl get po -A` 로 본다 (Kubeflow 는 `default` 가 아닌 네임스페이스에 있다).

**두 번째 사용자**(외부에 공유할 계정): `.env` 에 `EXTRA_USER_EMAIL`(소문자 이메일 형식, 실제 메일일 필요 없음)과 `EXTRA_USER_PASSWORD`(12자 이상)를 넣고 `06-2-extra-user.sh` 를 실행한다. Dex 로그인 계정과 Profile(네임스페이스 `kubeflow-<이메일의 @ . _ 를 - 로 바꾼 값>`)이 만들어지고, 소유자는 자기 네임스페이스에서만 `kubeflow-admin` 권한을 가진다. 할당량은 `06-2` 가 아니라 `06-4-quotas.sh` 가 `quotas.env` 의 값(기본: 파드 20개, 스토리지 20Gi, GPU 0개)으로 건다 (`06-2` 뒤에 실행. 그 전에는 할당량이 없다, [ADR 0015](../docs/decisions/0015-profile-resource-quota.md)). `06` 이 Dex 설정을 매번 기본값으로 되돌리므로 `06` 이 끝에서 이 스크립트를 다시 부른다. 비밀번호를 바꾸려면 `.env` 를 고치고 `06-2` 를 다시 실행한다. 사용자를 지우려면 `kubectl delete profile <이름>`(네임스페이스도 함께 지워진다)과 `.env` 의 두 줄 삭제 후 `06` 재실행이 필요하다 (이 삭제 경로는 시험하지 않았다).

## 접속 방식 (ADR 0011)

Kubeflow 공식 문서의 기본 접속은 `kubectl port-forward` 이고, NodePort 는 권하지 않는다. 웹앱(Jupyter 등)이 Secure 쿠키를 써서 **localhost 가 아닌 주소에 HTTP 로 접속하면 동작하지 않기** 때문이다. 그래서 게이트웨이 Service 는 ClusterIP 로 두고 다음처럼 쓴다. 근거와 NodePort 를 쓰지 않는 이유는 [ADR 0011](../docs/decisions/0011-no-nodeport-https-via-tailscale-serve.md).

| 어디서 | 방법 | 주소 |
|---|---|---|
| 이 PC (Windows 브라우저 포함) | `07-1-port-forward.sh` | `http://localhost:8080` |
| tailnet 의 다른 기기 (핸드폰 등) | `07-1` + `07-3-tailscale-serve.sh` | `https://<기기>.<tailnet>.ts.net` |
| tailnet 밖의 사람 (Tailscale 계정 없음) | `07-1` + `07-3` + `07-4-tailscale-funnel.sh on` (공유용 계정은 `06-2`) | 위와 같은 주소. 관리자 로그인 화면도 공개되므로 공유할 때만 켠다 |

- **이 PC 의 Windows 브라우저에서는 tailnet 주소(`100.x.x.x`)로 접속되지 않는다.** Tailscale 이 WSL 안에만 있어서 Windows 에는 그 주소가 없다 (2026-10-26: `:8080`, `:30080` 모두 타임아웃, `ipconfig` 에 주소 없음). 이 PC 는 `localhost` 를 쓴다.
- `07-3` 은 Tailscale 관리 콘솔의 DNS 페이지에서 **MagicDNS 와 HTTPS Certificates** 를 켜야 한다. 아직 시험하지 못했다.
- `07-2-nodeport.sh` 는 **사용하지 않는다.** 시험 기록으로 남긴 스크립트다. 2026-10-27 부터 `kind-config.yaml` 에 30080 매핑이 없어 새 클러스터에서는 안내하고 멈춘다.
- kind API 서버는 `127.0.0.1:6443` 에만 연다 (ADR 0010). **다른 기기에서 `kubectl` 은 쓰지 않는다.** 필요하면 tailnet 으로 SSH 해서 이 PC 에서 쓴다 (`tailscale serve --tcp` 로 여는 방법은 시험하지 않았다).
- 쿠키 때문에 클러스터를 다시 만든 뒤 옛 쿠키가 남은 브라우저는 `06` 이 `cookie-secret` 을 새로 만들어 로그인 화면으로 돌아간다 ([troubleshooting.md](../docs/troubleshooting.md) 23번).

## 재부팅 후 자동 복구

재부팅하거나 유휴가 지나면 WSL 이 꺼져 모든 것이 내려간다. 사람이 로그인하지 않아도 돌아오게 하는 구성이고, 근거와 미검증 항목은 [ADR 0010](../docs/decisions/0010-reboot-recovery.md).

```powershell
# 관리자 PowerShell
powershell -ExecutionPolicy Bypass -File .\windows\autostart.ps1        # 부팅 때 WSL 을 띄우는 예약 작업
powershell -ExecutionPolicy Bypass -File .\windows\power-settings.ps1   # AC 전원에서 절전 끄기
```
```bash
bash scripts/05-1-kind-cluster.sh   # 이미 만든 클러스터라면 다시 실행해 노드 재시작 정책을 적용 (멱등)
# 재부팅 후
bash scripts/verify/08-reboot.sh
```

## 클러스터만 다시 만들기

`kind-config.yaml` 이나 `cluster.env` 를 바꾸면(예: CPU 워커 수) 클러스터를 지우고 `05-1` 부터 다시 해야 한다. kind 는 만든 뒤에 노드나 포트 매핑을 바꿀 수 없다. Windows 와 WSL 설치(`00` ~ `04`)와 `07` 서비스는 그대로 둔다.

```bash
kind delete cluster --name mlops       # Kubeflow 와 그 안의 데이터(PV)가 사라진다
bash scripts/05-1-kind-cluster.sh
bash scripts/05-2-gpu-node.sh          # GPU 노드 컨테이너의 설정은 클러스터와 함께 사라지므로 다시 한다
bash scripts/05-3-device-plugin.sh
bash scripts/06-kubeflow.sh            # .env 의 비밀번호도 다시 반영된다
bash scripts/verify/07-1-port-forward.sh
# port-forward 방식은 systemd 서비스가 그대로 있으니 다시 할 것이 없다 (클러스터가 뜨면 다시 연결된다)
```

`teardown/05-kind-cluster.sh` 로 지워도 되지만 kind 와 kubectl 바이너리와 inotify 설정까지 지우고, `05-1` 이 다시 설치한다. 클러스터만 지우려면 위 한 줄이 가볍다. 클러스터가 없는 동안 `07` 서비스는 5초마다 재시작을 반복할 뿐 해가 없고, 새 클러스터가 뜨면 다시 연결된다 (추론, 시험 전).

## 삭제

설치의 역순으로 지운다. 되돌릴 수 없으므로 먼저 `DRY_RUN=1` 로 확인한다. 사용법은 [teardown/README.md](teardown/README.md).
