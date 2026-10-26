# 0012. 00~06 과 ADR 0001~0008 을 공식 문서와 다시 대조

- 상태: 기록 (2026-10-26)

## 상황
`00`~`06` 스크립트와 ADR 0001~0008 중 일부는 공식 문서를 읽기 전에 알던 지식으로 썼다 (ADR 0008 의 삭제 명령은 이미 대조했고, 0009~0011 은 쓸 때 대조했다). 규칙은 "만들기 전에 공식 안내를 읽고, 확인한 수준을 구분해 적는다"이다. 그래서 같은 방식으로 되돌아가 대조했다.

## 방법과 한계
- 각 공식 페이지에서 해당 부분(명령, 설정 필드, 버전, 날짜)을 **인용 형태로 추출**해 스크립트와 줄 단위로 비교했다.
- 추출은 페이지 전체가 아니라 질문에 맞는 **발췌**다. 발췌에 없는 것은 '문서에 없다'가 아니라 **'이번에 확인하지 못함'**으로 적는다.
- 판정: **일치** / **차이** (문서와 다름, 이유 기록) / **문서 밖** (문서에 없는 제 판단이나 관찰) / **미확인**.

## 스크립트 대조

| 대상 | 공식 문서가 말하는 것 | 이 저장소 | 판정 |
|---|---|---|---|
| `00` WSL 설치 | `wsl --install`, `--no-distribution`, `--distribution`, `wsl --list --quiet` 가 기본 명령에 있다. Virtual Machine Platform 은 수동 설치 때 `dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart` 로 켠다 | 같은 명령을 쓴다. VMP 는 `Enable-WindowsOptionalFeature ... -NoRestart` 로 켠다 | 일치 (VMP 는 같은 기능을 켜는 PowerShell 대응이고, 문서의 명령과 글자가 같지는 않다. 문서는 `wsl --install` 이 필요한 기능을 켠다고 하므로 0단계는 필수가 아니다) |
| `00` `.wslconfig` | `%UserProfile%\.wslconfig`, 모든 WSL 2 배포판에 적용 | 같은 위치에 복사 | 일치 |
| `01` systemd | `/etc/wsl.conf` 에 `[boot]` `systemd=true`, `wsl.exe --shutdown` 으로 재시작. `wsl --version` 이 인식되는 WSL 이 필요 | 같은 내용. `wsl --version` 은 스크립트가 확인하지 않는다 | 일치 (한계: 구버전 WSL 검사 없음) |
| `02` Tailscale 설치 | `curl -fsSL https://tailscale.com/install.sh \| sh`, `sudo tailscale up` | 같다 | 일치 |
| `02` `--ssh` | 현재 문서의 SSH 켜기는 `tailscale set --ssh`. 새 tailnet 의 기본 ACL 은 본인 기기로의 SSH 를 check 모드로 허용하고, 대상 기기에서 따로 켜야 한다 | `tailscale up --ssh` | **미확인** (`up --ssh` 형식이 이번에 가져온 페이지에 없었다) |
| `03` Docker 저장소 | deb822 `docker.sources` 의 필드 6개, 키링 `/etc/apt/keyrings/docker.asc` | 줄 단위로 같고, 이 PC 의 `/etc/apt/sources.list.d/docker.sources` 도 같은 내용이다 | 일치 |
| `03` 설치와 버전 고정 | `apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`, 버전은 `docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING` | 같다. 29.8.2 는 문서 예시 버전과 같다 | 일치 |
| `03` 문서 밖 | `apt-mark hold` 는 문서에 없다. `containerd-snapshotter: false` 는 kind#3795 의 **작업 우회 방법**으로 나온다 (이슈는 아직 열려 있다). `usermod -aG docker $USER`, `newgrp docker` 는 post-install 문서에 있고 "docker 그룹은 root 권한과 같다"는 경고가 붙는다 | 모두 수행. 경고는 스크립트에 적지 않았다 | 일치 / 문서 밖 (경고 누락) |
| `04` 저장소와 패키지 | 키링 경로, 패키지 4개, 버전 형식 `1.20.1-1`, `nvidia-ctk runtime configure --runtime=docker`, `systemctl restart docker` | 같다. `--set-as-default --cdi.enabled`, `accept-nvidia-visible-devices-as-volume-mounts=true` 를 더한다 | 일치. 더한 옵션은 install-guide 에 없고 **nvkind README 에 같은 명령이 있다** |
| `05-1` kind 와 노드 이미지 | kind v0.33.0 릴리스 노트에 노드 이미지 1.34.11, 1.35.8, 1.36.4, 1.37.0 과 digest 가 있고 기본값은 1.37.0 | `v1.36.4` 와 digest `sha256:099e0493...` 가 같다 | 일치 |
| `05-1` kubectl | `https://dl.k8s.io/release/<버전>/bin/linux/amd64/kubectl` 과 `.sha256`, `echo "$(cat kubectl.sha256)  kubectl" \| sha256sum --check` | 같은 URL 형식과 검증. 문서는 `stable.txt` 의 최신을 받고 우리는 버전을 고정한다 | 일치 (고정은 의도) |
| `05-1` kind 설정 필드 | `apiServerAddress/Port`, `extraMounts(hostPath, containerPath)`, `extraPortMappings(listenAddress)`, 노드별 `image`, `kubeadmConfigPatches` 가 있다 | 같은 필드 | 일치 |
| `05-1` API 서버 주소 | **"기본값 127.0.0.1 을 유지하길 강하게 권장"**, "kind 를 공개로 노출하기 전에 세 번 생각하라", "loopback 이외로 노출하는 것을 강하게 권하지 않는다" | `apiServerAddress` 를 **tailnet 주소**로 연다 (`k8s/kind-config.yaml`) | **차이** (아래 '발견 1') |
| `05-1` 노드 재시작 정책 | (스크립트 주석이 Docker 문서를 인용: kind 노드는 `on-failure:1`) | `docker update --restart unless-stopped` | **미확인** (이번에 해당 Docker 페이지를 읽지 않았다. 재부팅 시험으로는 동작을 확인했다, ADR 0010) |
| `05-2` 노드 안 containerd | nvkind README 발췌는 호스트 `nvidia-ctk` 설정과 마커 마운트를 설명한다. **노드 안에서 containerd 를 따로 설정하는 단계는 발췌에 없었다** | 노드 안에 toolkit 을 설치하고 `nvidia-ctk runtime configure --runtime=containerd ...` | **문서 밖 / 실측** (ADR 0006 이 nvkind `node.go` 를 읽어 확인했고, 이것이 없으면 device plugin 이 죽는 것을 실행으로 봤다) |
| `05-3` device plugin | `kubectl create -f .../deployments/static/nvidia-device-plugin.yml`, 전제는 nvidia 가 기본 런타임 | 같은 URL 형식 (README 예시는 v0.17.1, 우리는 v0.20.1), 전제 충족 | 일치 |
| `05-3` nodeSelector | README 발췌에 static 매니페스트의 nodeSelector 이야기가 없다 | `nodeSelector` 패치를 더한다 | **실측** (CPU 노드에서 NVML 을 못 찾고 계속 죽는 것을 봤다, ADR 0007) |
| `06` 설치 명령 | `while ! kustomize build example \| kubectl apply --server-side --force-conflicts -f -; do echo "Retrying to apply resources"; sleep 20; done` (끝없이 재시도) | 같은 명령을 **최대 10번**, 20초 간격으로 재시도 | **차이** (유한 재시도는 의도한 안전장치다. 10번으로 부족하면 다시 실행한다) |
| `06` 접속과 계정 | `kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80`, 기본 계정 `user@example.com` / `12341234` | 같다 | 일치 |
| `06` 자원 | 권장 RAM 16GB 이상, CPU 8코어 | RAM 16GB 미만이면 중단 (CPU 는 검사하지 않음) | 일치 (CPU 검사 없음) |
| `06` Dex 해시 | 문서 예시는 `htpasswd -BinC 10` 이 만든 bcrypt 이고 접두사는 **`$2a$`** | 파이썬의 `$2b$` 를 `$2y$` 로 바꾼다. 주석은 "문서의 예시는 `$2y$`" 라고 적혀 있었다 | **차이** (주석이 틀렸다. 고쳤다. `$2y$` 로 로그인되는 것은 실측으로 확인했다) |
| `06` kustomize 5.8.1, 체크섬 | - | - | **미확인** (이번에 가져오지 않았다) |

## ADR 대조

| ADR | 주장 | 이번 확인 | 판정 |
|---|---|---|---|
| 0001 | 24.04 표준 보안 지원 **2029년 4월**, 26.04 는 2026년 4월 출시 | ubuntu.com 표: 24.04 **May 2029**, 26.04 Released Apr 2026 | 24.04 종료일 **틀림, 고침** (4월 -> 5월). 26.04 출시는 일치 |
| 0002 | Kubeflow 문서가 kind 를 기본 테스트 환경으로 쓴다 | 26.03.1 README: "We use Kind as default" | 일치 |
| 0003 | kind v0.33.0 은 1.34~1.37 노드 이미지, 기본 1.37.0, `v1.36.4` digest, Kubeflow 26.03.1 CI 는 1.36 | 릴리스 노트의 이미지 목록과 digest 일치, 릴리스 페이지에 "Kind 0.32+ and Kubernetes 1.36 CI tests" | 일치 |
| 0004 | Docker 29.8.2 는 2026-09-30, 29.9.0 은 10-08, 최소 API 1.44, 새 설치는 containerd 이미지 스토어 기본, kind#3795 | 릴리스 노트: 29.8.2 2026-09-30, 29.9.0 2026-10-08, 최소 API v1.44, containerd 이미지 스토어 fresh install 기본. kind#3795 는 열려 있고 `containerd-snapshotter: false` 가 우회로로 적혀 있다 | 일치. 이후 29.9.1(10-14), 29.9.2(10-20)이 나왔고 `apt` 후보는 29.9.2 다. hold 로 29.8.2 를 유지한다 |
| 0005 | Kubeflow 26.03.1 은 2026-06-15, 26.10 은 아직 없음, 번들 Istio 1.30.1, Knative 1.22.0, cert-manager 1.20.2, Pipelines 2.16.1, KServe 0.18.0, Hub 제외로 메모리 약 2.1GiB·디스크 20GB 절약, 약 6개월 best-effort 지원 | 릴리스 페이지: 26.03.1 Jun 15, 26.10 없음 (2026-10-26). README 표의 버전이 모두 같고, Hub 는 2112Mi/20GB, best-effort 6개월 문장이 있다. 표에는 Notebooks v1.11.0, Katib v0.19.0 도 있다 | 일치. ADR 의 "Notebooks 개별 버전은 확인하지 못했다"는 이번에 v1.11.0 으로 확인했다 |
| 0006 | nvkind 의 `nvidia-ctk` 명령과 `/dev/null` 마커 마운트, toolkit 1.20.1 에 WSL2 CDI 수정 포함 | nvkind README 의 명령과 마커 마운트 예시가 같다. 1.20.1 릴리스 노트 발췌에는 "On WSL2, CDI discovery now includes additional ..." 문장이 있으나 **추출이 깨져 어느 버전의 항목인지 가를 수 없었다** | 명령은 일치. 'WSL2 수정이 1.20.1 에 있다'는 **미확인** |
| 0006 | Blackwell 은 CUDA 12.8 이상 필요 | 이번에 확인하지 않음 | **미확인** (ADR 에도 '알려져 있다'로 적혀 있다) |
| 0007 | kind 필드와 동작 | 설정 필드는 kind 문서와 일치 | 일치. 노드 수, 자원 측정은 설계와 실측이라 문서 대조 대상이 아니다 |
| 0008 | 삭제 명령 | 이미 2026-10-23 에 대조했다 | 이번에는 다시 하지 않았다 |

## 발견

1. **kind API 서버를 tailnet 주소로 여는 것은 kind 문서의 권고와 다르다.** 문서는 loopback 외 노출을 강하게 권하지 않는다. 우리 구성은 공개 인터넷이나 LAN 이 아니라 **tailnet 주소 하나**에만 바인딩하고 (`0.0.0.0` 이 아님), 같은 PC 밖의 `kubectl` 접근과 인증서 SAN 이 그 이유였다. 하지만 이 이탈과 근거는 어느 ADR 에도 적혀 있지 않았다.
   - **결정 (2026-10-26, 사용자): 다른 기기에서 `kubectl` 을 쓰므로 tailnet 바인딩을 유지한다.** loopback 으로 되돌리지 않는다 (되돌리려면 클러스터를 다시 만들어야 하는 점도 이유다).
   - **알고 쓰는 위험**: kind 는 업데이트 수단이 없고 보안이 최신 수준이 아니라는 것이 문서의 경고다. tailnet 의 기본 접근 정책은 **tailnet 의 모든 기기에 접근을 허용**한다 (Tailscale SSH 문서의 기본 ACL 설명). 그래서 tailnet 에 다른 기기나 사용자가 들어오면 6443 에 닿을 수 있다. 인증은 `kubectl` 자격 증명이 한다 (kind 기본 kubeconfig 의 인증 방식은 이 PC 에서 확인하지 않았다).
   - **대책 후보**: Terraform 단계에서 tailnet ACL 로 이 기기의 6443 접근을 본인 기기로 제한한다.
2. `02` 의 `--ssh` 가 현재 문서의 형식(`tailscale set --ssh`)과 다르다. 동작하는지는 이 대조로 알 수 없다.
3. 문서와 달랐던 두 곳은 고쳤다: ADR 0001 의 지원 종료일, `06` 의 Dex 해시 주석. 둘 다 동작에는 영향이 없다.

## 아직 확인하지 못한 것
`02` 의 `--ssh`, `05-1` 노드 재시작 정책의 Docker 문서 인용, `06` 의 kustomize 5.8.1 과 체크섬, ADR 0006 의 toolkit 1.20.1 WSL2 수정과 CUDA 12.8 요구, `05-2` 노드 안 containerd 단계(문서 근거 없음).

## 출처 (확인 2026-10-26)
- https://learn.microsoft.com/en-us/windows/wsl/install
- https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- https://learn.microsoft.com/en-us/windows/wsl/wsl-config
- https://tailscale.com/docs/install/linux
- https://tailscale.com/kb/1193/tailscale-ssh
- https://docs.docker.com/engine/install/ubuntu/
- https://docs.docker.com/engine/install/linux-postinstall/
- https://docs.docker.com/engine/release-notes/29/
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/release-notes.html
- https://github.com/NVIDIA/nvkind
- https://github.com/NVIDIA/k8s-device-plugin
- https://kind.sigs.k8s.io/docs/user/configuration/
- https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0
- https://github.com/kubernetes-sigs/kind/issues/3795
- https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- https://github.com/kubeflow/community-distribution (README, 26.03.1 태그의 README, releases)
- https://dexidp.io/docs/connectors/local/
- https://ubuntu.com/about/release-cycle
