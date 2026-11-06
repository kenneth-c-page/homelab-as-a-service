# Building and importing the website image for k3s

`services/website/compose.yml` uses `build: .`. Kubernetes cannot run Compose
builds, so the image has to be built first and then either pushed to a registry
or imported into the k3s containerd image store.

The k3s manifest expects an image named `astrowind:latest` with
`imagePullPolicy: IfNotPresent`. All of the build inputs stay in this
directory: `Dockerfile`, `nginx/nginx.conf`, the Astro source, and
`build-and-import.sh`.

## Build

From the repository root:

```bash
docker compose -f services/website/compose.yml build
# or
docker build -t astrowind:latest services/website
```

The `image: astrowind:latest` line in `compose.yml` makes Compose tag the built
image with the name the manifest expects.

## Option A: import into k3s containerd (no registry)

Run the helper from WSL/Linux:

```bash
services/website/build-and-import.sh
```

It builds `astrowind:latest`, saves it to `/tmp/astrowind-image.tar`, and imports
it into the local k3s containerd if `k3s` is installed on the same machine.

If you build on a different machine from the cluster, copy the tarball to every
node and import it there:

```bash
scp /tmp/astrowind-image.tar master:/tmp/
ssh master 'sudo k3s ctr -n k8s.io images import /tmp/astrowind-image.tar'

# Repeat on worker1, worker2, and worker3, or use a loop:
for host in worker1 worker2 worker3; do
  scp /tmp/astrowind-image.tar "$host:/tmp/"
  ssh "$host" 'sudo k3s ctr -n k8s.io images import /tmp/astrowind-image.tar'
done
```

The Deployment has no `nodeSelector`, so it can schedule on any node; the image
must be present on every node it might use.

Verify the import:

```bash
sudo k3s ctr -n k8s.io images ls | grep astrowind
```

## Option B: push to a registry

```bash
docker tag astrowind:latest ghcr.io/<owner>/homelab-website:latest
docker push ghcr.io/<owner>/homelab-website:latest
```

Then change the `image:` in `k3s/deployments/lucas.yml` to the registry
reference. If the registry is private, add an `imagePullSecret` to the
`website` Deployment.

## Updating the site

After rebuilding and re-importing (or pushing), restart the Deployment so it
picks up the new image:

```bash
kubectl rollout restart deployment/website -n 344-group-project
```

If you use a registry and keep the `latest` tag, the manifest's
`imagePullPolicy: IfNotPresent` can reuse a cached copy on the node. Either set
`imagePullPolicy: Always` for that Deployment or push a unique tag/digest and
update the manifest.

## Notes

- Do not commit the `.tar` image; it is a build artifact. It is ignored by
  `services/website/.gitignore` if you choose to keep it here.
- If you prefer to keep the tarball in this directory, run:
  `TARBALL=./astrowind-image.tar services/website/build-and-import.sh`
- The first build can take a few minutes because the Astro site is built with
  Node before the final nginx image is produced.
