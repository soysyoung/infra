# 0007. kind 를 4노드(control-plane 1, GPU 워커 1, CPU 워커 2)로 구성

- 상태: 채택 (2026-10-23, 검증 완료)

## 상황
Kubeflow 를 올리기 전에 노드 구성을 정한다. 단일 노드에서는 GPU 작업과 CPU 작업이 한 노드에 섞이고, 스케줄링(taint, toleration, nodeSelector)을 실습할 수 없다.

## 결정
- 노드: control-plane 1 + **GPU 워커 1** + **CPU 워커 2** (Docker 컨테이너 4개).
- GPU 워커(`mlops-worker`)에만 NVIDIA 마커 마운트, 라벨 `nvidia.com/gpu.present=true`, taint `nvidia.com/gpu=present:NoSchedule`.
- 스크립트를 수명이 다른 세 단계로 나눈다: `05-1` 클러스터, `05-2` GPU 노드 설정, `05-3` device plugin. Kubeflow 는 06 그대로 둔다.

## 근거
- GPU 노드와 CPU 노드를 나누면 Pipelines 의 CPU 단계(전처리)와 GPU 단계(학습)를 노드로 분리하는 실제 MLOps 패턴을 실습할 수 있다. `cordon`/`drain`, PodDisruptionBudget 도 실습 가능하다.
- CPU 워커를 3개가 아니라 **2개**로 했다: kind 는 워커가 있으면 control-plane 에 일반 파드를 올리지 않는다. CPU 노드 3개와 2개는 스케줄링 실습 면에서 새로 배우는 것이 거의 없고 자원만 더 쓴다.
- 스크립트를 나눈 이유: 클러스터 생성, GPU 노드 후처리(노드 하나의 호스트 쪽 설정), 애드온 설치는 수명과 실패 원인이 다르다. 나누면 검증이 단계별로 분리되고, 05-1 까지만 하면 GPU 없이도 유효한 클러스터가 된다. 이후 Terraform 에서도 클러스터(kind provider)와 애드온(`helm_release`)으로 나뉘는 것이 자연스럽다.

## 측정 (2026-10-23, 유휴 상태, `docker stats`)
| 노드 | 메모리 |
|---|---|
| control-plane | 약 694 MiB |
| GPU 워커 | 약 267 MiB |
| CPU 워커 (각) | 약 148 MiB |
| 합계 | 약 1.26 GiB |

WSL 의 `free -h` 사용량은 클러스터 생성 전 1.5Gi 에서 후 2.1Gi 였다. Kubeflow 를 올리기 전의 값이라 Kubeflow 부하에서의 오버헤드는 측정하지 않았다.

## 한계와 주의
- 물리 자원은 이 노트북 하나(WSL 24GB, 24코어)다. 노드를 늘려도 용량은 늘지 않는다. **고가용성이 아니라 스케줄링 실습용 구성**이다.
- 노드마다 containerd 가 따로라 같은 이미지를 노드별로 받는다 (디스크는 충분).
- 기본 스토리지가 노드 로컬이라 PVC 를 쓰는 파드는 PVC 가 만들어진 노드에 묶인다.
- device plugin 의 공식 static 매니페스트에는 `nodeSelector` 가 없어서, `05-3` 이 GPU 라벨로 제한한다 (안 그러면 CPU 노드에서 NVML 을 못 찾아 계속 죽는다). 이 동작은 `verify/05-3` 이 `desiredNumberScheduled=1` 로 확인한다.
- 라벨과 taint 는 kubeadm 설정 버전(v1beta3/v1beta4)에 따라 kubeletExtraArgs 형식이 달라서, 클러스터 생성 후 `kubectl` 로 건다.
- GPU 워커는 kind 가 붙이는 이름 `mlops-worker`(config 의 첫 번째 워커)에 의존한다. 이후 단계는 라벨로 GPU 노드를 찾는다.

## 재검토 시점
Kubeflow 부하에서 메모리가 부족하면 CPU 워커를 줄인다. 재부팅 후 기동 순서를 확인할 때 다시 본다.
