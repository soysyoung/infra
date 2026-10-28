#!/usr/bin/env bash
# 05-4. Helm 설치 (체크섬 검증)
#
# 왜: OpenSearch 공식 설치 방법이 Helm 차트다 (09). 버전은 versions.env 의 HELM_VERSION, 근거는 docs/decisions/0014.
# 검증: scripts/verify/05-4-helm.sh
#
# 참고 (공식 문서): https://helm.sh/docs/intro/install/
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

if helm version --short 2>/dev/null | grep -q "^${HELM_VERSION}"; then
  log "helm ${HELM_VERSION} 가 이미 있습니다."
else
  asset="helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tmp=$(mktemp -d)
  curl -fsSL "https://get.helm.sh/$asset" -o "$tmp/$asset"
  curl -fsSL "https://get.helm.sh/$asset.sha256sum" -o "$tmp/$asset.sha256sum"
  (cd "$tmp" && sha256sum -c "$asset.sha256sum")
  tar -xzf "$tmp/$asset" -C "$tmp"
  sudo install -m 0755 "$tmp/linux-amd64/helm" /usr/local/bin/helm
  rm -rf "$tmp"
fi
log "완료. 검증: scripts/verify/05-4-helm.sh"
