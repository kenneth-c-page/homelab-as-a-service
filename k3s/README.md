# k3s

Apply the shared namespace first, then the deployment manifests:

```bash
kubectl apply -f k3s/namespace.yml
kubectl apply -f k3s/deployments/lucas.yml
```

Lucas's services:

- `deployments/lucas.yml` - Authentik, Pi-hole + Unbound, and the website.
- `lucas-secrets.md` - required Secret generation and replacement.
- `lucas-ingress.md` - optional migration from LoadBalancer ports to Traefik
  Ingress hostnames.
- `../services/website/k3s-image.md` - building and importing the website image.

The kubeconfig is fetched by `ansible/playbooks/run-deployments.yml` to
`k3s/k3s_config`, which is gitignored.

## Notes

- Replace the placeholder Secret values before exposing anything; see
  `lucas-secrets.md`.
- The Pi-hole PVC starts empty. The checked-in `services/pihole/etc-pihole`
  directory is not mounted into the cluster; copy it into the PVC after the pod
  starts if you need the existing configuration.
- Pi-hole DNS listens on port 53. If the nodes already run `systemd-resolved`,
  see the DNS note in `lucas-ingress.md`.
- The website image must be built and imported, or pushed to a registry; see
  `../services/website/k3s-image.md`.
