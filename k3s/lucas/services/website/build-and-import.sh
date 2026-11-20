#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE="${IMAGE:-astrowind:latest}"
TARBALL="${TARBALL:-/tmp/astrowind-image.tar}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required to build the website image" >&2
  exit 1
fi

echo "==> Building ${IMAGE}"
docker build -t "${IMAGE}" .

echo "==> Saving ${IMAGE} to ${TARBALL}"
docker save "${IMAGE}" -o "${TARBALL}"

if command -v k3s >/dev/null 2>&1; then
  echo "==> Importing ${IMAGE} into the local k3s containerd"
  sudo k3s ctr -n k8s.io images import "${TARBALL}"
  echo "Done. If the Deployment is already running, restart it:"
  echo "  kubectl rollout restart deployment/website -n 344-group-project"
else
  cat <<EOF
k3s was not found on this machine.

Copy ${TARBALL} to each cluster node and import it there:

  sudo k3s ctr -n k8s.io images import ${TARBALL}

Or push the image to a registry and update k3s/deployments/lucas.yml.
EOF
fi
