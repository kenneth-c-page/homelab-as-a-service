# Deploying Lucas's services

This guide covers the updated authentik layout (separate server and worker
pods) and the website image published to GHCR.

## Prerequisites

- The `344-group-project` namespace exists:
  ```bash
  kubectl apply -f k3s/namespace.yml
  ```
- The `homelab-secrets` Secret exists. For a fresh cluster, create it from
  `k3s/secrets.example.yml`:
  ```bash
  cp k3s/secrets.example.yml k3s/secrets.local.yml
  # edit k3s/secrets.local.yml and replace the placeholders
  kubectl apply -f k3s/secrets.local.yml
  ```
  On the existing cluster the Secret already exists; do **not** apply the
  example file over it. See [lucas-secrets.md](lucas-secrets.md).
- The website image is published at
  `ghcr.io/kenneth-c-page/homelab-website:latest`. The GitHub Actions workflow
  in `.github/workflows/website-image.yml` builds it on pushes to `main`.
  Make the package public in the repository's package settings, or add an
  `imagePullSecret` if you keep it private.

## Longhorn RWX preflight

`authentik-data` is now `ReadWriteMany`. Before applying the manifest, verify
that a Longhorn RWX volume is writable by UID 1000:

```bash
kubectl -n 344-group-project apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rwx-preflight
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: rwx-preflight
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
    - name: test
      image: docker.io/library/busybox:1.37
      command:
        - sh
        - -c
        - |
          set -eu
          touch /data/preflight
          echo "write ok"
          ls -ld /data /data/preflight
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: rwx-preflight
EOF

kubectl -n 344-group-project wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/rwx-preflight --timeout=180s

kubectl -n 344-group-project logs rwx-preflight
```

The pod should print `write ok`. Clean up:

```bash
kubectl -n 344-group-project delete pod rwx-preflight
kubectl -n 344-group-project delete pvc rwx-preflight
```

If the write fails with a permission error, do not proceed with RWX. Either
fix the volume permissions (for example with a root init container that chowns
`/data`) or fall back to ReadWriteOnce and pin the server and worker pods to
the same node.

## One-time migration from the old single-pod authentik Deployment

The old `authentik` Deployment ran the server and worker in one pod. That layout
cannot work with authentik 2026.8.5 because both processes bind the same TCP
and Unix-socket ports. The new manifest replaces it with
`authentik-server` and `authentik-worker`.

`kubectl apply` does not delete resources that are no longer in the file, so do
this once:

```bash
# Confirm the old Deployment is already scaled to zero.
kubectl -n 344-group-project get deployment authentik
kubectl -n 344-group-project get pods -l app=authentik

# Remove the old Deployment and its ReplicaSet.
kubectl -n 344-group-project scale deployment authentik --replicas=0
kubectl -n 344-group-project delete deployment authentik

# Recreate the /data volume as ReadWriteMany.
# The authentik setup never completed, so there is no data to preserve.
kubectl -n 344-group-project delete pvc authentik-data
kubectl -n 344-group-project get pvc authentik-data

# Do NOT delete authentik-postgres-data. The database stays.
```

Wait until `authentik-data` is gone before applying the manifest. Longhorn may
take a few seconds to detach and delete the old volume.

## Apply

```bash
kubectl apply -f k3s/deployments/lucas.yml
```

The manifest sets Postgres, the authentik server/worker, and the website to one
replica. The authentik init containers wait for Postgres, and the worker waits
for the server's readiness endpoint before starting.

Publish the website image and make the GHCR package public **before** applying,
otherwise the new pod repeats the old `ImagePullBackOff`. If you need to apply
first, keep the website at zero and scale it up after the package is public:

```bash
kubectl -n 344-group-project scale deployment/website --replicas=0
```

## Watch the first start

```bash
kubectl -n 344-group-project get pods -l app=authentik -w
```

In separate terminals:

```bash
kubectl -n 344-group-project logs -f deployment/authentik-server
kubectl -n 344-group-project logs -f deployment/authentik-worker
```

The worker pod stays in `Init:0/2` until the server reports ready. If the
server crashes, troubleshoot it first and capture the previous log:

```bash
kubectl -n 344-group-project logs deployment/authentik-server --previous
```

Both Deployments set `AUTHENTIK_LOG_LEVEL=debug` for the first boot. Once the
server is stable, change that value to `info` in
`k3s/deployments/lucas.yml` and re-apply.

## Validate

```bash
# RWX volume
kubectl -n 344-group-project get pvc authentik-data \
  -o jsonpath='{.spec.accessModes}{"\n"}'

# Only the server pod should be behind the Service.
kubectl -n 344-group-project get endpoints authentik-server

# Worker healthcheck
kubectl -n 344-group-project exec deployment/authentik-worker -- ak healthcheck

# UI and website. Use any node IP.
curl -I http://192.168.1.165:9000/
curl -I http://192.168.1.165:9876/

# Website image pull
kubectl -n 344-group-project get pods -l app=website
kubectl -n 344-group-project describe pod -l app=website
```

If the website pod is in `ErrImagePull` or `ImagePullBackOff`, check that the
GHCR package is public and that the image path in `lucas.yml` matches the
package owner. For a private package, create a pull secret and reference it
from the `website` Deployment.

## Rollback / stop

Scale the authentik pods down without deleting the volumes:

```bash
kubectl -n 344-group-project scale deployment authentik-server authentik-worker --replicas=0
```

The old single-pod Deployment is not a safe rollback target because of the
shared-port conflicts. If you need to go back to the previous git revision,
expect the same crash loop until the server and worker are separated again.
`authentik-postgres-data` is retained; `authentik-data` is recreated as part of
the migration.
