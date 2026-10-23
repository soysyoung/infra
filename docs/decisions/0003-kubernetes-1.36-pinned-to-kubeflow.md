# 0003. Kubernetes 1.36 (kindest/node v1.36.4), Kubeflow 에 맞춰 고정

- 상태: 채택 (2026-10-23)

## 상황
Kubernetes 마이너 버전을 정해야 한다. kind v0.33.0 은 1.34 ~ 1.37 노드 이미지를 제공하고 기본값은 1.37.0 이다.

## 결정
`kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed`

## 근거
- Kubeflow 26.03.1 의 CI 가 Kubernetes 1.36 에서 돈다. 검증된 조합을 쓴다.
- 1.37 은 kind 의 기본값이지만 Kubeflow 가 검증하지 않았다. 안정성 우선 원칙으로 제외.
- 태그가 아니라 **digest** 로 고정해서 같은 이미지가 재현되게 한다.
- k3s stable 채널도 1.36(v1.36.5+k3s1)이라 k3s 로 돌아가도 같은 마이너를 유지한다.

## 재검토 시점
Kubeflow 가 다음 릴리스에서 지원 Kubernetes 버전을 올릴 때.

## 출처 (확인 2026-10-23)
- https://github.com/kubernetes-sigs/kind/releases (v0.33.0 의 노드 이미지 목록)
- https://github.com/kubeflow/community-distribution/releases (26.03.1: Kubernetes 1.36 CI)
- https://update.k3s.io/v1-release/channels
