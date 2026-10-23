# 0008. 삭제는 설치의 역순, 안전장치 포함, 공식 문서와 대조

- 상태: 채택 (2026-10-23, 일부 미시험)

## 상황
처음부터 재현 가능한지 확인하려면 환경을 깨끗이 지울 수 있어야 한다. 삭제는 되돌릴 수 없고 순서에 따라 실패하는 부분이 있다.

## 결정
- 설치의 역순으로 지운다: `06 -> 05 -> 04 -> 03 -> 02` (WSL 안, `scripts/teardown/all.sh`), 마지막에 `00` (Windows, PowerShell). `01` 은 배포판 안의 `/etc/wsl.conf` 라서 배포판과 함께 사라진다.
- **04 는 `daemon.json` 을 03 이 만든 상태로 먼저 되돌리고 Docker 를 재시작한 뒤 패키지를 지운다.** 거꾸로 하면 Docker 가 없어진 nvidia 런타임을 찾다가 시작에 실패한다 (제 추론, 아래 표 참고).
- 안전장치: `yes` 입력이 없으면 취소(앞뒤 공백/대소문자 무시, `y` 같은 약식은 거부), `DRY_RUN=1` / `-DryRun` 은 명령만 출력, 이미 지워진 항목은 건너뛴다.
- 02(Tailscale)는 원격 접속을 끊으므로 WSL 안에서 맨 뒤에 둔다.

## 공식 문서 대조 (2026-10-23)

삭제 명령은 처음에 제가 알던 지식으로 썼고, 삭제를 실행한 **뒤에** 공식 문서와 대조했다.

| 대상 | 공식 문서 | 이 스크립트 | 판정 |
|---|---|---|---|
| Docker 패키지 | `apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras` ([문서](https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine)) | 동일 (`docker-ce-rootless-extras` 는 처음에 빠졌다가 삭제 점검에서 발견해 추가) | 일치 |
| Docker 데이터 | `rm -rf /var/lib/docker /var/lib/containerd` | 동일 | 일치 |
| Docker apt 저장소 | `docker.sources`(deb822), 키링 `/etc/apt/keyrings/docker.asc` | `03-docker.sh` 가 만드는 `docker.list` 와 `docker.sources` **둘 다** 삭제 | **차이**: 설치 스크립트가 옛 형식(`docker.list`)을 쓴다. 동작은 하지만 현재 문서와 다르다 |
| Docker 설정 파일 | "편집한 설정 파일은 직접 지운다" | `/etc/docker` 삭제 | 일치 |
| Tailscale | `apt-get remove tailscale`, 완전 삭제는 `/var/lib/tailscale/tailscaled.state` 제거 ([문서](https://tailscale.com/docs/features/client/uninstall)) | `purge` + `/var/lib/tailscale` 통째로 삭제 | 상위 집합 (문서보다 더 지운다) |
| Tailscale 로그아웃, 저장소/키링 제거, `tailscale-archive-keyring` 패키지 | 문서에 없음 | 스크립트가 추가로 수행 | **문서 근거 없음** (제 판단) |
| kind 클러스터 | `kind delete cluster [--name]`, 없는 클러스터는 오류 없이 넘어감(멱등) ([문서](https://kind.sigs.k8s.io/docs/user/quick-start/)) | 동일 (`kind get clusters` 가드는 중복이지만 무해) | 일치 |
| kubeconfig 정리 | 해당 페이지에 설명 없음 | 이 PC 에서 삭제 후 `~/.kube/config` 의 kind 항목이 0개임을 **관찰** | 문서 근거 없음 (관찰로만 확인) |
| WSL 배포판 | `wsl --terminate`, `wsl --unregister` 는 "모든 데이터, 설정, 소프트웨어가 영구히 사라진다", `wsl --list --quiet` ([문서](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)) | 동일, 같은 경고를 출력 | 일치 |
| NVIDIA Container Toolkit | 설치 안내서의 패키지 4개와 `nvidia-container-toolkit.list` 이름은 일치. **삭제 절차는 찾지 못했다** (안내서 페이지 추출이 비어 있어 확인 불가) | `daemon.json` 복원 후 4개 패키지 purge, 저장소 파일/키링 삭제 | **문서 근거 없음** (제 추론: 복원 후 삭제 순서) |
| inotify 복원(128), `apt-mark unhold`, `ip link delete docker0`, `gpasswd -d` | 해당 문서 없음 (일반 리눅스 관리 명령) | 수행 | 문서 근거 없음 |

정리: **핵심 삭제 명령은 공식 문서와 일치**한다. 문서에 없는 부분(NVIDIA 삭제 순서, Tailscale 로그아웃, 인터페이스 정리 등)은 제 추론이거나 이 PC 에서의 관찰이고, 위 표에 그렇게 표시했다. NVIDIA 삭제는 가장 근거가 약하다.

## 한계
- 실제 삭제는 한 번 실행했고, 그 점검에서 발견한 잔재(패키지 2개, `docker0`)를 고친 경로는 **아직 시험하지 못했다.**
- NVIDIA 삭제 순서와 Tailscale 로그아웃 등은 문서 근거가 없는 제 판단이다.
- `03-docker.sh` (설치)는 옛 형식의 `docker.list` 를 만든다. 현재 공식 문서는 `docker.sources` (deb822) 이다. 동작은 하지만 문서와 다르다.

## 재검토 시점
재설치 후 다시 삭제할 때 고친 경로와 "삭제 확인" 기대 결과를 실제 출력으로 확인한다.

## 출처 (확인 2026-10-23)
- https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine
- https://tailscale.com/docs/features/client/uninstall
- https://kind.sigs.k8s.io/docs/user/quick-start/
- https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html (설치만, 삭제 절차는 찾지 못함)
