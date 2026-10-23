# 아키텍처

노트북 한 대를 원격 MLOps 서버로 만든다. 접속은 Tailscale 하나로 일원화하고 공유기 포트포워딩은 쓰지 않는다.

```
[원격 클라이언트: 노트북/휴대폰]  (Tailscale 설치, kubectl)
        |  tailnet (WireGuard)   ssh / kubectl --server https://<tailnet 주소>:6443
        v
+-- Windows 11 Home 노트북 (RTX 5080, 32GB) -------------------------------+
|  NVIDIA 드라이버 (Windows 쪽만)                                          |
|  .wslconfig: memory 24GB, mirrored 네트워킹                              |
|                                                                          |
|  +-- WSL2 Ubuntu 24.04 (systemd) -------------------------------------+  |
|  |  tailscaled        <- tailnet 노드 (WSL 이 직접 가입)  [완료: 02]  |  |
|  |  Docker Engine 29.8.2                                  [완료: 03]  |  |
|  |  NVIDIA Container Toolkit 1.20.1                       [설치: 04]  |  |
|  |     |                                                              |  |
|  |     +-- kind 클러스터 (노드 = Docker 컨테이너)         [예정: 05]  |  |
|  |           kindest/node v1.36.4                                     |  |
|  |           +-- Kubeflow 26.03.1                         [예정: 06]  |  |
|  +--------------------------------------------------------------------+  |
+--------------------------------------------------------------------------+
```

`[완료]`, `[설치]`, `[예정]` 은 2026-10-23 기준이다. 검증까지 끝난 것은 02, 03 이다.

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
| 05 | WSL | kind 클러스터 (예정) |
| 06 | WSL | Kubeflow (예정) |

## IaC 전환 계획 (설치 완료 후)

Terraform 으로 tailscale ACL/authkey 와 클러스터 플랫폼 구성을 코드화하고, Kubeflow 는 kustomize 기반이라 ArgoCD 로 배포한다 (`iac/`, 아직 만들지 않았다).
