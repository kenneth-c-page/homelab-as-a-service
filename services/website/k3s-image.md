# Building and publishing the website image for k3s

`services/website/compose.yml` uses `build: .`. Kubernetes cannot run Compose
builds, so the image is built ahead of time and published to a registry.

The manifest expects:

```yaml
image: ghcr.io/kenneth-c-page/homelab-website:latest
imagePullPolicy: Always
```

The `.github/workflows/website-image.yml` workflow builds
`services/website/Dockerfile` on every push to `main` that changes the website,
then pushes `:latest` and a SHA tag to GHCR.

## Publish from GitHub Actions

1. Push the workflow and website changes to `main`.
2. Open the repository's **Actions** tab and wait for **Build website image**.
3. In the repository/package settings, set the `homelab-website` package
   visibility to **Public** so the cluster can pull it without a secret.

If you keep the package private, create a pull secret in the cluster and add it
to the `website` Deployment:

```bash
kubectl -n 344-group-project create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username='<github-user>' \
  --docker-password='<PAT with read:packages>'
```

Then add:

```yaml
imagePullSecrets:
  - name: ghcr-pull
```

under `spec.template.spec` in the `website` Deployment.

## Publish manually

From a machine with Docker:

```bash
docker build -t ghcr.io/kenneth-c-page/homelab-website:latest services/website

echo "$GHCR_TOKEN" | docker login ghcr.io -u '<github-user>' --password-stdin
docker push ghcr.io/kenneth-c-page/homelab-website:latest
```

Use a personal access token with `write:packages` for the push. The workflow
uses `GITHUB_TOKEN` instead.

## Local import fallback (no registry)

The manifest now uses GHCR, so the local-import path requires changing the
image back to `astrowind:latest` with `imagePullPolicy: IfNotPresent`. The
image must be present on every node the pod can schedule to; the Deployment has
no `nodeSelector`.

Build and save:

```bash
docker build -t astrowind:latest services/website
docker save astrowind:latest -o /tmp/astrowind-image.tar
```

Or use the helper:

```bash
services/website/build-and-import.sh
```

It imports into the local k3s containerd when run on a cluster node. From a
different machine, copy the tarball to each node and import it:

```bash
for host in master worker-1 worker-2 worker-3; do
  scp /tmp/astrowind-image.tar "$host:/tmp/"
  ssh "$host" 'sudo k3s ctr -n k8s.io images import /tmp/astrowind-image.tar'
done
```

Verify on each node:

```bash
sudo k3s ctr -n k8s.io images ls | grep astrowind
```

Then set the manifest to:

```yaml
image: astrowind:latest
imagePullPolicy: IfNotPresent
```

## Updating the site

After the workflow pushes a new `:latest`, restart the Deployment so the pod
pulls it:

```bash
kubectl rollout restart deployment/website -n 344-group-project
```

Because the manifest uses `imagePullPolicy: Always`, a pod restart always checks
GHCR for the current `:latest` image.

## Notes

- The image is prebuilt nginx serving Astro's `dist` output. `npm` and the
  Astro build run only at image build time, not when the pod starts.
- Do not commit image tarballs. `services/website/.gitignore` ignores them if
  you keep them in that directory.
- The first build can take a few minutes because the Astro site is built with
  Node before the final nginx image is produced.
