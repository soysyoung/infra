# TODO

앞으로 할 일과 시험할 것. 끝낸 항목은 지우지 않고 결과를 적어 남긴다. 막힌 곳은 [troubleshooting.md](troubleshooting.md), 결정 근거는 [decisions/](decisions/).
`[ ]` 아직 안 함, `[x]` 끝남 (결과 기록).

## 지금: 재부팅 후 자동 복구 시험 ([ADR 0010](decisions/0010-reboot-recovery.md))

구성은 끝났고(2026-10-23) 시험 전이다. 순서대로 한다.

- [x] 관리자 PowerShell: `windows\autostart.ps1` (부팅 때 WSL 을 띄우는 예약 작업 `wsl-keepalive`) -> 등록됨 (2026-10-26: 상태 Ready, 로그온 S4U, **한 번도 실행되지 않음**: 마지막 결과 0x41303 = 아직 실행 전)
- [x] 관리자 PowerShell: `windows\power-settings.ps1` (AC 절전 끄기). 실행 후 `powercfg /query` 로 값 확인 -> AC 절전/최대 절전 0 확인 (`powercfg /query`, 2026-10-26)
- [x] 덮개 닫기 동작: 제어판에서 '아무 것도 안 함' 으로 설정, `powercfg /qh SCHEME_CURRENT SUB_BUTTONS LIDACTION` 으로 AC/DC 모두 0 확인 (2026-10-23). 덮개를 닫은 채로도 접속되는지는 재부팅 시험 때 같이 본다
- [x] WSL: `bash scripts/05-1-kind-cluster.sh` (노드 재시작 정책 `unless-stopped` 적용, 멱등) -> 4개 노드 모두 `unless-stopped` 확인 (08 출력)
- [ ] **(아직 안 함)** Windows **다시 시작(Restart)**, **로그인하지 않고** 몇 분 대기 -> 핸드폰에서 `http://<tailnet 주소>:8080` 접속
- [ ] 로그인 후 WSL: `bash scripts/verify/08-reboot.sh`, 출력을 [verify/README.md](../scripts/verify/README.md) 에 붙인다 (재부팅 **전** 상태로 한 번 실행해 통과, 아래 참고)
- [ ] 확인할 위험: S4U 로 실행한 `wsl.exe` 가 배포판을 띄우고 유지하는가 / `tailscaled` 가 Docker 보다 늦게 떠서 노드가 실패하지 않는가 / 재시작 뒤 kind 노드 IP 가 바뀌지 않는가

2026-10-26 점검: 사용자가 08 을 실행해 통과했지만 **재부팅 시험은 아직 하지 않은 상태**다. 근거(이 PC 에서 직접 조회):
- WSL 가동 시간 2일 12시간, `uptime -s` = 2026-10-23 21:58. Windows 부팅 시각 2026-10-19 09:17, 그 뒤 종료/재시작 이벤트(id 1074/6006)는 10-19 18:07 이 마지막이다. 재부팅했다면 WSL VM 도 새로 시작해 가동 시간이 짧아야 한다.
- `wsl-keepalive` 의 LastRunTime 이 1999-11-30(기본값), 결과 0x41303 이라 한 번도 실행되지 않았다.
- 08 의 노드 재시작 정책, 서비스, 노드 Ready, 방식 A 접속은 **재부팅 없이도** 통과한다. 재부팅이 만드는 차이(WSL 이 저절로 뜨는가, 노드가 저절로 뜨는가)는 아직 보지 못했다.
- 관찰: autostart 작업 없이도 WSL 이 2일 넘게 꺼지지 않았다. 컨테이너와 서비스가 돌고 있으면 유휴 종료가 일어나지 않는 것으로 보이지만(추정), 재부팅 뒤에는 WSL 을 띄우는 주체가 필요해서 작업은 그대로 둔다.
- 위험: 빠른 시작(Fast Startup)이 켜져 있다 (`HiberbootEnabled=1`). 종료 후 다시 켜는 방식은 커널 세션을 이어 가서 부팅 시각이 바뀌지 않고 '시스템 시작' 트리거가 도는지 불확실하다 (미검증). **시작 메뉴의 '다시 시작'** 으로 시험한다.

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
