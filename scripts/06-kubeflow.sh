#!/usr/bin/env bash
# 06. Kubeflow 설치 (Pipelines, Notebooks, KServe + 필수 공통요소)
#
# 왜: ML 파이프라인, 노트북, 모델 서빙을 한 플랫폼에서 쓰기 위해.
# 하는 일:
#   1) kustomize 를 체크섬 검증 후 설치 (공식 테스트 버전, versions.env)
#   2) 공식 저장소를 KUBEFLOW_VERSION 태그로 ~/.cache/infra 에 클론
#   3) k8s/kubeflow/kustomization.yaml (공식 example 에서 Katib/Trainer/Spark/Hub 만 뺀 것)을 복사해 빌드, server-side apply
#   4) Istio CNI 가 Ready 가 되도록 보장하고, CNI 없이 만들어져 Init:Error 에 멈춘 파드를 지워 다시 만들게 함
#   5) 핵심 네임스페이스의 Deployment 가 Available 이 될 때까지 대기
#   여러 번 실행해도 안전하다 (server-side apply). 중간에 실패하면 같은 명령을 다시 실행하면 된다.
#
# 포함되는 공통요소: cert-manager, Istio, Dex, oauth2-proxy, Knative Serving (KServe 기본 모드가 Serverless)
# 주의: 기본 로그인은 user@example.com / 12341234 이다. 클러스터는 tailnet 에서만 열려 있지만 비밀번호를 바꾸기 전에는 외부에 노출하지 않는다.
#
# 선행: 05-1 ~ 05-3 (RAM 은 WSL 에 16GB 이상 권장, 첫 설치는 이미지를 많이 받아 오래 걸린다)
# 검증: scripts/verify/06-kubeflow.sh
#
# 참고 (공식 문서):
#   - 설치: https://github.com/kubeflow/community-distribution#installation
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd kubectl "05-1-kind-cluster.sh 를 먼저 하세요."
require_cmd git
kubectl get nodes >/dev/null || die "클러스터에 접속할 수 없습니다. 05-1-kind-cluster.sh 를 먼저 하세요."
[ "$(free -g | awk '/^Mem:/{print $2}')" -ge 16 ] || die "WSL 메모리가 16GB 미만입니다 (.wslconfig 확인)."
[ "$(sysctl -n fs.inotify.max_user_instances)" -ge "$INOTIFY_MAX_USER_INSTANCES" ] \
  || die "inotify 한도가 부족합니다 (Istio CNI 가 죽습니다). 05-1-kind-cluster.sh 를 먼저 실행하세요."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if ! kustomize version 2>/dev/null | grep -q "$KUSTOMIZE_VERSION"; then
  asset="kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
  base="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}"
  curl -fsSL "$base/$asset" -o "$tmp/$asset"
  curl -fsSL "$base/checksums.txt" | grep "  $asset\$" > "$tmp/checksums.txt"
  (cd "$tmp" && sha256sum -c checksums.txt)
  tar -xzf "$tmp/$asset" -C "$tmp" kustomize
  sudo install -m 0755 "$tmp/kustomize" /usr/local/bin/kustomize
fi

# /mnt/c 는 파일 수가 많으면 느리므로 WSL 홈에 둔다.
SRC="$HOME/.cache/infra/kubeflow-$KUBEFLOW_VERSION"
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone -q --depth 1 --branch "$KUBEFLOW_VERSION" https://github.com/kubeflow/community-distribution.git "$SRC"
fi
mkdir -p "$SRC/example-mlops"
cp "$ROOT/k8s/kubeflow/kustomization.yaml" "$SRC/example-mlops/kustomization.yaml"

# CRD 와 웹훅이 준비되기 전에 적용되는 리소스가 있어 첫 시도는 실패할 수 있다. 공식 설치도 재시도 루프를 쓴다.
for i in $(seq 10); do
  if (cd "$SRC" && kustomize build example-mlops | kubectl apply --server-side --force-conflicts -f -); then
    applied=1; break
  fi
  log "적용 재시도 $i/10 (20초 후)"; sleep 20
done
[ "${applied:-}" = 1 ] || die "Kubeflow 적용에 실패했습니다."

# Istio CNI 가 준비되기 전에 스케줄된 파드는 istio-validation 이 실패해 Init:Error 에서 멈추고 스스로 복구되지 않는다.
# CNI 가 Ready 가 된 뒤 그런 파드만 지우면 Deployment 가 CNI 가 있는 상태로 다시 만든다.
# CNI 가 CrashLoopBackOff 의 재시도 대기에 걸려 있으면 재시작해서 대기를 건너뛴다.
kubectl -n kube-system rollout status ds/istio-cni-node --timeout=30s \
  || { kubectl -n kube-system rollout restart ds/istio-cni-node; kubectl -n kube-system rollout status ds/istio-cni-node --timeout=300s; }
kubectl get pods -A --no-headers | awk '$4 ~ /^Init:(Error|CrashLoopBackOff)/ {print $1, $2}' \
  | while read -r ns p; do kubectl -n "$ns" delete pod "$p" --wait=false; done

for ns in cert-manager istio-system auth oauth2-proxy knative-serving kubeflow-system kubeflow; do
  # kubeflow-system 처럼 Deployment 가 없는 네임스페이스에는 kubectl wait 가 실패하므로 건너뛴다.
  [ -n "$(kubectl -n "$ns" get deploy -o name)" ] || continue
  kubectl wait --for=condition=Available deployment --all -n "$ns" --timeout=900s
done

log "완료. 검증: scripts/verify/06-kubeflow.sh"
echo "접속: kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80  ->  http://localhost:8080"
