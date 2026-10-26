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
#   +) .env 의 비밀번호를 dex 에 반영하고, oauth2-proxy 의 cookie-secret 을 설치마다 새로 만든다 (옛 브라우저 쿠키 무효화)
#   여러 번 실행해도 안전하다 (server-side apply). 중간에 실패하면 같은 명령을 다시 실행하면 된다.
#
# 포함되는 공통요소: cert-manager, Istio, Dex, oauth2-proxy, Knative Serving (KServe 기본 모드가 Serverless)
# 주의: 로그인은 user@example.com, 비밀번호는 .env 의 KUBEFLOW_PASSWORD (없으면 공개된 기본값 12341234). 바꾸기 전에는 외부에 노출하지 않는다.
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

# .env 의 KUBEFLOW_PASSWORD 를 bcrypt 해시로 dex 에 반영한다 (없으면 공식 기본값 유지). apply 가 매번 기본값으로 되돌리므로 매번 한다.
pw=$(sed -n 's/^KUBEFLOW_PASSWORD=//p' "$ROOT/.env" 2>/dev/null | tr -d '\r')
if [ -n "$pw" ]; then
  python3 -c 'import bcrypt' 2>/dev/null || die "python3-bcrypt 가 필요합니다. sudo apt install python3-bcrypt"
  # dex 문서의 예시는 htpasswd -BinC 10 이 만든 bcrypt 해시($2a$ 로 적혀 있음)다. htpasswd -B 가 내는 $2y$ 로 맞춘다 (파이썬은 $2b$ 를 낸다). $2y$ 로 로그인되는 것은 확인했다.
  hash=$(PW="$pw" python3 -c 'import bcrypt,os;print(bcrypt.hashpw(os.environ["PW"].encode(),bcrypt.gensalt(12)).decode().replace("$2b$","$2y$",1))')
  kubectl -n auth patch secret dex-passwords -p "{\"stringData\":{\"DEX_USER_PASSWORD\":\"$hash\"}}"
  kubectl -n auth rollout restart deploy/dex   # 비밀번호는 시작할 때만 읽는다
fi

# oauth2-proxy 의 cookie-secret 은 매니페스트에 공개된 고정값이다. 그대로면 클러스터를 다시 만들어도 브라우저에 남은 옛 세션 쿠키가
# 통과하고, 옛 dex 키로 서명된 토큰이 붙어 게이트웨이가 "Jwks doesn't have key" 401 을 낸다 (troubleshooting 24번).
# 설치마다 새로 만들어 옛 쿠키를 무효로 한다. 이미 로그인한 브라우저는 06 을 다시 실행할 때마다 로그인 화면으로 돌아간다.
# Secret 이름에는 kustomize 가 해시를 붙이므로 Deployment 가 참조하는 이름을 읽는다.
require_cmd openssl
cs=$(kubectl -n oauth2-proxy get deploy oauth2-proxy -o jsonpath="{.spec.template.spec.containers[*].env[?(@.name=='OAUTH2_PROXY_COOKIE_SECRET')].valueFrom.secretKeyRef.name}")
[ -n "$cs" ] || die "oauth2-proxy 의 cookie-secret 시크릿 이름을 찾지 못했습니다."
kubectl -n oauth2-proxy patch secret "$cs" -p "{\"stringData\":{\"cookie-secret\":\"$(openssl rand -hex 16)\"}}"
kubectl -n oauth2-proxy rollout restart deploy/oauth2-proxy   # 환경변수는 시작할 때만 읽는다

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

# apply 가 Dex 설정을 기본값(사용자 1명)으로 되돌렸으므로, .env 에 두 번째 사용자가 있으면 다시 반영한다 (없으면 건너뜀).
bash "$ROOT/scripts/06-2-extra-user.sh"

log "완료. 검증: scripts/verify/06-kubeflow.sh"
echo "접속: kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80  ->  http://localhost:8080"
