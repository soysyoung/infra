#!/usr/bin/env bash
# 05. kind + kubectl 설치, GPU 지원 클러스터 생성, NVIDIA device plugin 설치
#
# 왜: Kubeflow 를 올릴 단일 노드 Kubernetes. 노드가 Docker 컨테이너라 런타임이 Docker 하나다.
# 하는 일:
#   1) kind, kubectl 을 체크섬 검증 후 /usr/local/bin 에 설치 (버전은 versions.env)
#   2) k8s/kind-config.yaml 로 클러스터 'mlops' 생성 (API 서버는 tailnet 주소에 바인딩)
#   3) 노드 컨테이너 안에 NVIDIA toolkit 설치 + 노드의 containerd 를 nvidia 런타임으로 설정
#   4) NVIDIA device plugin 설치
#   kubeconfig 는 ~/.kube/kind-mlops.yaml 에 따로 쓴다 (기존 ~/.kube/config 는 건드리지 않음)
#
# 선행: 02-tailscale.sh (인증서 SAN 에 tailnet 주소가 들어간다), 03-docker.sh, 04-nvidia-toolkit.sh
# 검증: scripts/verify/05-kind.sh
#
# 참고 (공식 문서):
#   - kind 설정: https://kind.sigs.k8s.io/docs/user/configuration/
#   - GPU 설정(nvkind): https://github.com/NVIDIA/nvkind#setup
#   - device plugin: https://github.com/NVIDIA/k8s-device-plugin
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

CLUSTER=mlops
KUBECONFIG_FILE="$HOME/.kube/kind-mlops.yaml"

require_cmd docker "03-docker.sh 를 먼저 하세요."
require_cmd tailscale "02-tailscale.sh 를 먼저 하세요."
require_cmd envsubst "sudo apt-get install -y gettext-base"
[ "$(docker info --format '{{.DefaultRuntime}}')" = nvidia ] || die "Docker 기본 런타임이 nvidia 가 아닙니다. 04-nvidia-toolkit.sh 를 먼저 하세요."

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
else
  envsubst '${TAILNET_IP} ${KIND_NODE_IMAGE}' < "$ROOT/k8s/kind-config.yaml" \
    | kind create cluster --name "$CLUSTER" --config - --kubeconfig "$KUBECONFIG_FILE"
fi
chmod 600 "$KUBECONFIG_FILE"
export KUBECONFIG="$KUBECONFIG_FILE"

# 호스트 Docker 설정만으로는 노드 안의 containerd 가 파드에 GPU 라이브러리를 넣지 못한다
# (device plugin 이 NVML 을 못 찾고 죽는다). nvkind 처럼 노드 안에도 toolkit 을 설치하고 containerd 를 설정한다.
NODE="$CLUSTER-control-plane"
if ! docker exec "$NODE" test -f /etc/containerd/conf.d/99-nvidia.toml; then
  docker exec -i -e V="$NVIDIA_TOOLKIT_VERSION-1" -e DEBIAN_FRONTEND=noninteractive "$NODE" bash -s <<'EOS'
set -e
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg >/dev/null
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -qq
apt-get install -y -qq "nvidia-container-toolkit=$V" "nvidia-container-toolkit-base=$V" \
  "libnvidia-container-tools=$V" "libnvidia-container1=$V" >/dev/null
nvidia-ctk runtime configure --runtime=containerd --config-source=file --set-as-default --cdi.enabled
systemctl restart containerd
EOS
  kubectl wait --for=condition=Ready node --all --timeout=120s
fi

kubectl apply -f "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$DEVICE_PLUGIN_VERSION/deployments/static/nvidia-device-plugin.yml"
kubectl -n kube-system rollout status daemonset/nvidia-device-plugin-daemonset --timeout=180s

log "완료. 다음 줄을 ~/.bashrc 에 추가하세요:"
echo "  export KUBECONFIG=\$HOME/.kube/kind-mlops.yaml"
echo "검증: scripts/verify/05-kind.sh"
