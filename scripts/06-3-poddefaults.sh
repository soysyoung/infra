#!/usr/bin/env bash
# 06-3. 기본 사용자 네임스페이스에 PodDefault 2개를 적용
#
# 왜: Notebook 생성 화면의 Configurations 에서 고르는 값이다. 재설치하면 사라지므로 스크립트로 둔다.
#   - gpu-toleration: GPU 워커의 taint(nvidia.com/gpu=present:NoSchedule)를 견딘다. 없으면 GPU Notebook 이 스케줄되지 않는다.
#   - access-ml-pipeline: Notebook 안의 kfp.Client() 가 쓰는 토큰을 넣는다.
# 선행: 06-kubeflow.sh (프로필 네임스페이스는 Kubeflow 가 만든다). 검증: scripts/verify/06-3-poddefaults.sh
# 삭제 스크립트는 없다: PodDefault 는 클러스터 안에만 있어서 삭제 05(클러스터 삭제)와 함께 사라진다.
#
# 참고 (공식 문서): https://www.kubeflow.org/docs/components/pipelines/user-guides/core-functions/connect-api/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

NS=kubeflow-user-example-com
for _ in $(seq 30); do kubectl get ns "$NS" >/dev/null 2>&1 && break; sleep 2; done
kubectl get ns "$NS" >/dev/null 2>&1 || die "네임스페이스 $NS 가 없습니다. 06-kubeflow.sh 가 끝났는지 확인하세요."

kubectl apply -f "$ROOT/k8s/gpu-poddefault.yaml" -f "$ROOT/k8s/access-ml-pipeline-poddefault.yaml"
log "완료. 검증: scripts/verify/06-3-poddefaults.sh"
