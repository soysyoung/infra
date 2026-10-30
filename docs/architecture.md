# 아키텍처

노트북 한 대를 원격 MLOps 서버로 만든다. 접속은 Tailscale 하나로 일원화하고 공유기 포트포워딩은 쓰지 않는다.

```
[원격 클라이언트: 노트북/휴대폰]  (Tailscale 설치)
        |  tailnet (WireGuard)   ssh / https://<기기>.<tailnet>.ts.net (Kubeflow)
        |  (kind API 서버는 이 PC 의 127.0.0.1 에만 열려 있다. 원격 kubectl 은 ssh 로 들어가 쓴다)
        v
+-- Windows 11 Home 노트북 (RTX 5080, 32GB) -------------------------------+
|  NVIDIA 드라이버 (Windows 쪽만)                                          |
|  .wslconfig: memory 24GB, mirrored 네트워킹                              |
|                                                                          |
|  +-- WSL2 Ubuntu 24.04 (systemd) -------------------------------------+  |
|  |  tailscaled        <- tailnet 노드 (WSL 이 직접 가입)  [완료: 02]  |  |
|  |  Docker Engine 29.8.2                                  [완료: 03]  |  |
|  |  NVIDIA Container Toolkit 1.20.1 (기본 런타임 nvidia)  [완료: 04]  |  |
|  |     |                                                              |  |
|  |     +-- kind 클러스터, 노드 4개 = Docker 컨테이너      [완료: 05]  |  |
|  |           control-plane / GPU 워커 / CPU 워커 x2 (v1.36.4)         |  |
|  |           +-- Kubeflow 26.03.1                         [완료: 06]  |  |
|  |           +-- OpenSearch 3.8.0 (Helm, 단일 노드)       [완료: 09]  |  |
|  |           +-- PostgreSQL 18.6 (CloudNativePG, 단일)    [완료: 10]  |  |
|  +--------------------------------------------------------------------+  |
+--------------------------------------------------------------------------+
```

`[완료]`, `[예정]` 은 2026-10-30 기준이다. 02 ~ 10 은 각 단계의 `verify` 를 통과했다. 10-1(PostgreSQL)은 `verify` 만 통과했고 그 뒤의 시험(재시작, 재설치, 백업)은 남았다. 10-2(Notebook 접속)는 스크립트만 만들었고 아직 실행하지 않았다 ([todo.md](todo.md) 31 ~ 34번). 접속은 07 의 port-forward 와 `tailscale serve` 이고, OpenSearch Dashboards 는 `:8443` 으로 따로 연다 (09-4).

## 설계 원칙

- **런타임은 Docker 하나.** kind 노드도, 이미지 빌드도 같은 Docker 를 쓴다 ([0004](decisions/0004-docker-single-runtime.md)).
- **Tailscale 은 WSL 안에.** 접속 경로가 tailnet 하나라 WSL 네트워킹 모드(NAT/mirrored)에 덜 민감하다. Windows 에는 설치하지 않았다.
- **버전은 `versions.env` 한 곳.** 스크립트와 이후 Terraform 이 같은 값을 읽는다 ([versions.md](versions.md)).
- **스크립트와 설정 분리.** 절차는 `scripts/`, 선언형 설정은 `k8s/` 에 둔다. IaC 단계에서 설정을 그대로 재사용한다.
- **단계마다 검증.** `scripts/verify/` 가 "설치됨" 이 아니라 "동작함" 을 확인한다.

## 실행 순서

| 단계 | 위치 | 내용 |
|---|---|---|
| 00 | Windows (관리자 PowerShell) | VM Platform, WSL, `.wslconfig`, Ubuntu 24.04 |
| 01 | WSL | systemd 활성화 |
| 02 | WSL | Tailscale 가입 (`--ssh`) |
| 03 | WSL | Docker Engine (버전 고정, containerd 이미지 스토어 끔) |
| 04 | WSL | NVIDIA Container Toolkit, Docker 런타임 설정 |
| 05-1 | WSL | kind 4노드 클러스터, GPU 노드에 라벨/taint |
| 05-2 | WSL | GPU 노드 컨테이너에 toolkit 설치, containerd 설정 |
| 05-3 | WSL | device plugin (GPU 노드에만) |
| 05-4 | WSL | Helm (09, 10 의 차트 설치용) |
| 06 | WSL | Kubeflow 26.03.1: Pipelines, Notebooks, KServe (+ Istio, Knative, cert-manager, Dex) |
| 06-2 ~ 06-4 | WSL | 두 번째 사용자(공유용), PodDefault(GPU toleration 등), 프로필 ResourceQuota |
| 07-1, 07-3, 07-4 | WSL | Kubeflow 접속: port-forward 서비스, `tailscale serve` HTTPS, (선택) Funnel |
| 08 | WSL | 재부팅·장애 복구 감시 서비스 |
| 09-1 ~ 09-5 | WSL | OpenSearch 3.8.0 단일 노드(k-NN), Dashboards, 게스트 계정, Dashboards tailnet/Funnel 노출, Notebook 용 접속 정보 주입 |
| 10-1 | WSL | PostgreSQL 단일 인스턴스: CloudNativePG 연산자(Helm) + Cluster. 클러스터 안에서만 접근, 비밀번호는 `.env` ([ADR 0021](decisions/0021-postgres-cloudnativepg.md)) |
| 10-2 | WSL | Notebook 에서 PostgreSQL 접속: 데이터 읽기/쓰기 전용 계정 `notebook_rw` + Secret + PodDefault, 기본 사용자와 공유용 네임스페이스 ([ADR 0022](decisions/0022-notebook-postgres-access.md)) |

## IaC 전환 계획 (설치 완료 후)

Terraform 으로 tailscale ACL/authkey 와 클러스터 플랫폼 구성을 코드화하고, Kubeflow 는 kustomize 기반이라 ArgoCD 로 배포한다 (`iac/`, 아직 만들지 않았다).
