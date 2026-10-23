#!/usr/bin/env bash
# 05-1. kind + kubectl 설치, 클러스터 생성(노드 수는 cluster.env), GPU 노드에 라벨/taint
#
# 왜: Kubeflow 를 올릴 Kubernetes. 노드가 Docker 컨테이너라 런타임이 Docker 하나다.
#     GPU 노드 1개와 CPU 노드를 나눠 GPU 작업만 GPU 노드로 보내는 스케줄링을 실습한다.
# 하는 일:
#   1) kind, kubectl 을 체크섬 검증 후 /usr/local/bin 에 설치 (버전은 versions.env)
#   0) WSL 의 inotify 인스턴스 한도를 cluster.env 의 INOTIFY_MAX_USER_INSTANCES 로 올림 (kind 노드가 커널을 공유해서 기본값 128 은 부족)
#   2) k8s/kind-config.yaml 로 클러스터 생성 (control-plane 1 + GPU 워커 1 + CPU 워커 CPU_WORKERS 개, cluster.env)
#   3) GPU 워커(mlops-worker)에 라벨 nvidia.com/gpu.present=true 와 taint nvidia.com/gpu=present:NoSchedule
#   접속 정보는 kind 공식 기본값대로 ~/.kube/config 에 병합된다 (컨텍스트 kind-mlops)
#
# 선행: 02-tailscale.sh (인증서 SAN 에 tailnet 주소가 들어간다), 03-docker.sh, 04-nvidia-toolkit.sh
# 다음: 05-2-gpu-node.sh -> 05-3-device-plugin.sh
# 검증: scripts/verify/05-1-kind-cluster.sh
#
# 참고 (공식 문서):
#   - kind 설정: https://kind.sigs.k8s.io/docs/user/configuration/
#   - taint 와 toleration: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_cmd docker "03-docker.sh 를 먼저 하세요."
require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."
require_cmd envsubst "sudo apt-get install -y gettext-base"
# GPU 노드의 마커 마운트는 Docker 의 기본 런타임이 nvidia 일 때만 동작한다.
[ "$(docker info --format '{{.DefaultRuntime}}')" = nvidia ] || die "Docker 기본 런타임이 nvidia 가 아닙니다. 04-nvidia-toolkit.sh 를 먼저 하세요."

# kind 노드 컨테이너는 WSL 커널을 공유한다. 기본 inotify 인스턴스 한도(128)로는 4노드 + Istio CNI 가
# 'too many open files' 로 죽는다. systemd 가 켜져 있어 /etc/sysctl.d 설정은 재부팅 후에도 유지된다.
if [ "$(sysctl -n fs.inotify.max_user_instances)" -lt "$INOTIFY_MAX_USER_INSTANCES" ]; then
  echo "fs.inotify.max_user_instances = $INOTIFY_MAX_USER_INSTANCES" | sudo tee /etc/sysctl.d/99-kind-inotify.conf >/dev/null
  sudo sysctl --system >/dev/null
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if ! kind version 2>/dev/null | grep -q "kind $KIND_VERSION "; then
  base="https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION"
  curl -fsSL "$base/kind-linux-amd64" -o "$tmp/kind-linux-amd64"
  curl -fsSL "$base/kind-linux-amd64.sha256sum" -o "$tmp/kind.sha256sum"
  (cd "$tmp" && sha256sum -c kind.sha256sum)
  sudo install -m 0755 "$tmp/kind-linux-amd64" /usr/local/bin/kind
fi

if ! kubectl version --client 2>/dev/null | grep -q "$KUBECTL_VERSION"; then
  base="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64"
  curl -fsSL "$base/kubectl" -o "$tmp/kubectl"
  curl -fsSL "$base/kubectl.sha256" -o "$tmp/kubectl.sha256"
  echo "$(cat "$tmp/kubectl.sha256")  $tmp/kubectl" | sha256sum -c
  sudo install -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
fi

TAILNET_IP=$(tailscale ip -4)
export TAILNET_IP KIND_NODE_IMAGE
mkdir -p "$HOME/.kube"

if kind get clusters | grep -qx "$CLUSTER"; then
  log "클러스터 '$CLUSTER' 가 이미 있습니다. 생성은 건너뜁니다."
  kind export kubeconfig --name "$CLUSTER"   # 접속 정보를 ~/.kube/config 에 (다시) 병합한다
else
  [[ "$CPU_WORKERS" =~ ^[0-9]+$ ]] || die "cluster.env 의 CPU_WORKERS 는 0 이상의 정수여야 합니다 (현재: '$CPU_WORKERS')."
  {
    envsubst '${TAILNET_IP} ${KIND_NODE_IMAGE}' < "$ROOT/k8s/kind-config.yaml"
    for _ in $(seq "$CPU_WORKERS"); do printf '  - role: worker\n    image: %s\n' "$KIND_NODE_IMAGE"; done
  } | kind create cluster --name "$CLUSTER" --config -
fi

# kind 노드의 재시작 정책은 on-failure:1 이라 Docker 데몬이 재시작(재부팅)되면 노드가 올라오지 않는다 (Docker 문서).
# unless-stopped 로 바꾸면 재부팅 후 노드가 자동으로 시작된다. 이미 만든 클러스터에도 적용된다.
docker update --restart unless-stopped $(kind get nodes --name "$CLUSTER") >/dev/null

# kubeadm 설정 버전(v1beta3/v1beta4)에 따라 kubeletExtraArgs 형식이 달라서, 라벨과 taint 는 생성 후 kubectl 로 건다.
kubectl label node "$CLUSTER-worker" "$GPU_LABEL" --overwrite
kubectl taint node "$CLUSTER-worker" nvidia.com/gpu=present:NoSchedule --overwrite
kubectl wait --for=condition=Ready node --all --timeout=180s

log "완료. 접속 정보는 kind 공식 기본값대로 ~/.kube/config 에 병합되었습니다 (컨텍스트: kind-$CLUSTER). 파드는 'kubectl get po -A' 로 봅니다."
echo "다음: scripts/05-2-gpu-node.sh"
