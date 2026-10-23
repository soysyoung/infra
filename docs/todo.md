# TODO

앞으로 할 일과 시험할 것. 끝낸 항목은 지우지 않고 결과를 적어 남긴다. 막힌 곳은 [troubleshooting.md](troubleshooting.md), 결정 근거는 [decisions/](decisions/).
`[ ]` 아직 안 함, `[x]` 끝남 (결과 기록).

## 지금: 재부팅 후 자동 복구 시험 ([ADR 0010](decisions/0010-reboot-recovery.md))

구성은 끝났고(2026-10-23) 시험 전이다. 순서대로 한다.

- [ ] 관리자 PowerShell: `windows\autostart.ps1` (부팅 때 WSL 을 띄우는 예약 작업 `wsl-keepalive`)
- [ ] 관리자 PowerShell: `windows\power-settings.ps1` (AC 절전 끄기). 실행 후 `powercfg /query` 로 값 확인
- [ ] 제어판 '덮개를 닫을 때 수행할 작업' 직접 확인 (이 PC 에서는 `powercfg` 로 덮개 설정이 조회되지 않았다)
- [ ] WSL: `bash scripts/05-1-kind-cluster.sh` (노드 재시작 정책 `unless-stopped` 적용, 멱등)
- [ ] Windows 재부팅, **로그인하지 않고** 몇 분 대기 -> 핸드폰에서 `http://<tailnet 주소>:8080` 접속
- [ ] 로그인 후 WSL: `bash scripts/verify/08-reboot.sh`, 출력을 [verify/README.md](../scripts/verify/README.md) 에 붙인다
- [ ] 확인할 위험: S4U 로 실행한 `wsl.exe` 가 배포판을 띄우고 유지하는가 / `tailscaled` 가 Docker 보다 늦게 떠서 노드가 실패하지 않는가 / 재시작 뒤 kind 노드 IP 가 바뀌지 않는가
- [ ] 결과를 ADR 0010 의 '미검증' 과 troubleshooting 열린 항목에 반영

## 방식 C (NodePort 직결) 시험 ([ADR 0009](decisions/0009-tailnet-exposure-a-vs-c.md))

방식 A 는 확인했다. C 는 호스트 포트 매핑이 **클러스터를 만들 때만** 정해져서, 지금 클러스터에는 없다.

- [ ] 재부팅 시험(위)을 끝낸 뒤에 한다. 클러스터를 다시 만들면 그 안의 Kubeflow 데이터가 사라진다.
- [ ] 클러스터만 다시 만들기: [scripts/README.md](../scripts/README.md) '클러스터만 다시 만들기'
- [ ] `bash scripts/verify/07-expose.sh` 에서 방식 C (`<tailnet 주소>:30080`) 가 OK 인지, A 와 공존하는지
- [ ] A 와 C 중 상시로 쓸 것을 정하고 ADR 0009 의 '결정' 을 갱신 (선호는 C)

## 기능 시험

- [ ] 로그인 후 기능: Pipelines 실행, Notebook 생성, GPU Notebook (아직 하나도 시험하지 않았다)
- [ ] Tailscale 관리 콘솔에서 쓰지 않는 offline 장치 7개 삭제 ([troubleshooting.md](troubleshooting.md) 5번)

## 재현성 검증 (재설치 마무리)

- [ ] `03` 의 `docker.sources` 저장소 등록을 `scripts/verify/03-docker.sh` 로 확인
- [ ] 삭제의 수정 경로(패키지 2개 purge, `docker0` 삭제)를 한 번 실행해 확인 ([troubleshooting.md](troubleshooting.md) 18번). `DRY_RUN=1` 로 먼저
- [ ] 이번 재설치 각 단계의 verify 출력을 [verify/README.md](../scripts/verify/README.md) 에 반영 (07 은 출력을 받지 못했다)
- [ ] 비밀번호 약함: `.env` 의 `KUBEFLOW_PASSWORD` 가 네 자리 숫자다. tailnet 밖으로 열기 전에 더 긴 값으로 바꾼다

## 문서

- [ ] `00`~`06`, ADR 0001~0008 을 ADR 0008 처럼 공식 문서와 다시 대조 (이번 세션은 0009, 0010 만 대조했다)

## 병합

- [ ] 위 검증이 끝나면 `dev` -> `main` PR. `main` 의 README 는 `dev` 를 가리키는 임시 링크와 안내 문구가 있으므로 충돌하면 `dev` 쪽 내용을 택한다
- [ ] `dev` 의 기존 커밋 48개는 작성자 이메일이 `dangim.co.kr` 이다 (히스토리를 다시 쓰지 않기로 했다)

## 이후

- [ ] IaC: Terraform 으로 tailscale ACL/authkey 와 클러스터 플랫폼 구성, ArgoCD 로 Kubeflow 배포 ([architecture.md](architecture.md))
