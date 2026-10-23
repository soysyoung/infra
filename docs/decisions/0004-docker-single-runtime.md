# 0004. Docker Engine 29.8.2, 단일 런타임

- 상태: 채택 (2026-10-23)

## 상황
kind 는 Docker 컨테이너를 노드로 쓴다. 이미지 빌드도 같은 Docker 로 한다. Docker 버전을 정해야 한다.

## 조사
- Docker 와 Kubernetes/Kubeflow 사이에 **공식 호환표는 없다.** kind 에서 Kubernetes 는 노드 이미지 안의 containerd 위에서 돌아 호스트 Docker 버전과 직접 묶이지 않는다. Kubeflow 문서도 Docker 버전을 요구하지 않는다("podman (better) or docker").
- Docker 29 는 최소 API 버전을 1.44 로 올렸다. 오래된 클라이언트가 깨진다.
- Docker 29 는 새 설치의 기본 이미지 스토어가 containerd 라서 `kind load docker-image` 가 실패할 수 있다 (kubernetes-sigs/kind#3795, 2026-09 에도 보고됨).

## 결정
- **29.8.2** (2026-09-30), Docker 공식 apt 저장소, `apt-mark hold` 로 고정.
- 선택 기준(휴리스틱, Docker 에 LTS 가 없다): 직전 마이너의 마지막 패치이고 다음 마이너(29.9.0, 10-08)가 나온 지 2주 이상 지난 것. 29.9.x 는 출시 직후라 제외.
- `/etc/docker/daemon.json` 에 `{"features": {"containerd-snapshotter": false}}` 를 넣어 containerd 이미지 스토어를 끈다 (`03-docker.sh`). 04 의 `nvidia-ctk` 가 이 파일에 병합한다.

## 검증 (2026-10-23, WSL Ubuntu 24.04)
`docker --version` = 29.8.2, 서비스 active, Storage Driver overlay2, hold 적용 확인.

## 대안
- Docker 28.x: 안정성이 더 낫다는 근거를 찾지 못했다.
- Podman: Kubeflow 문서는 "better" 라고 하나 이 프로젝트는 Docker 중심 도구(문서, CI 관행)를 쓴다.

## 재검토 시점
kind#3795 가 해결되면 snapshotter 설정을 제거할 수 있다. 보안 패치가 필요하면 29.8.x 안에서 올린다.

## 출처 (확인 2026-10-23)
- https://docs.docker.com/engine/install/ubuntu/
- https://docs.docker.com/engine/release-notes/29/
- https://github.com/kubernetes-sigs/kind/issues/3795
- https://github.com/moby/moby/releases (패치 날짜)
