# Secrets for Lucas's services

`k3s/deployments/lucas.yml` contains a `Secret` named `homelab-secrets` with
placeholder values. If you apply the manifest unchanged, the services will start
with those placeholders, so replace them before exposing anything.

## Values used

| Key | Used by | Notes |
| --- | --- | --- |
| `PG_PASS` | PostgreSQL and Authentik | Used as PostgreSQL's `POSTGRES_PASSWORD` and Authentik's `AUTHENTIK_POSTGRESQL__PASSWORD`. PostgreSQL does not accept passwords longer than 99 characters. |
| `AUTHENTIK_SECRET_KEY` | Authentik server and worker | Must be identical for both containers. Changing it after the first start can invalidate sessions and encrypted data. |
| `PIHOLE_PASSWORD` | Pi-hole | Admin/API password for the Pi-hole web UI. |

## Generate values

Run these in a terminal (WSL/Linux/macOS):

```bash
openssl rand -base64 36 | tr -d '\n'   # PG_PASS
openssl rand -base64 60 | tr -d '\n'   # AUTHENTIK_SECRET_KEY
openssl rand -base64 24 | tr -d '\n'   # PIHOLE_PASSWORD
```

Use a password manager or a password of your choice for the Pi-hole value.

## Option A: edit the manifest (simple, but secrets are in Git)

1. Open `k3s/deployments/lucas.yml`.
2. Replace the three values under `Secret` -> `stringData`.
3. Apply:

   ```bash
   kubectl apply -f k3s/deployments/lucas.yml
   ```

Do not commit real values. The `Secret` in the manifest is only a convenient
placeholder; Kubernetes Secrets are base64-encoded in etcd, not encrypted by
default. If real values are committed, rotate them.

## Option B: create the Secret separately (recommended)

Keep the real values out of the repository. If the `Secret` is still present in
`lucas.yml`, applying the manifest later will overwrite your real Secret with
the placeholders, so remove the `Secret` document from the tracked manifest or
keep your real values in a separate, untracked copy.

Create the Secret directly:

```bash
kubectl create secret generic homelab-secrets \
  -n 344-group-project \
  --from-literal=PG_PASS="$(openssl rand -base64 36 | tr -d '\n')" \
  --from-literal=AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')" \
  --from-literal=PIHOLE_PASSWORD='choose-a-strong-password' \
  --dry-run=client -o yaml > /tmp/homelab-secrets.yaml

kubectl apply -f /tmp/homelab-secrets.yaml -n 344-group-project
```

Then apply the rest of the manifest. For a GitOps workflow, use a tool such as
Sealed Secrets, SOPS, or External Secrets instead of committing plaintext.

## First start vs. rotation

- `POSTGRES_PASSWORD` is only used while PostgreSQL initializes its data
  directory. If you change `PG_PASS` after the first start, the database still
  has the old password and Authentik cannot connect. To change it later:

  ```bash
  kubectl exec -it deployment/authentik-postgresql -n 344-group-project -- \
    psql -U authentik -d authentik -c "ALTER USER authentik WITH PASSWORD 'new-password';"
  ```

  Then update the Secret and restart Authentik.
- Changing `AUTHENTIK_SECRET_KEY` after first start can invalidate sessions and
  encrypted data. Set it before the first start.
- Changing a Secret does not automatically restart pods. Restart the affected
  workloads after updating a Secret:

  ```bash
  kubectl rollout restart deployment/authentik \
    deployment/authentik-postgresql \
    deployment/pihole \
    -n 344-group-project
  ```

## Verify

```bash
kubectl get secret homelab-secrets -n 344-group-project
kubectl describe secret homelab-secrets -n 344-group-project
```

The values are not printed by `describe`; use `-o yaml` only when you really
need to inspect them.










Instructions
- k3s/lucas-secrets.md — generating PG_PASS, AUTHENTIK_SECRET_KEY, and PIHOLE_PASSWORD, replacing the placeholders, the separate kubectl create secret approach, and the important PostgreSQL password-rotation caveat.
- k3s/lucas-ingress.md — exact steps and YAML to switch the three HTTP services from LoadBalancer ports to Traefik Ingress with auth.344.local, pihole.344.local, and www.344.local. It also covers the port-53 conflict note with systemd-resolved.
- k3s/README.md — short index and apply commands.
Validation
- kubeconform -strict against Kubernetes 1.33: 15 valid, 0 invalid.
- Python structural checks: all namespaces, Deployment selectors, Service selectors, targetPort names, PVC references, and Secret references are consistent.
- bash -n services/website/build-and-import.sh: passes.
Apply
kubectl apply -f k3s/namespace.yml
kubectl apply -f k3s/deployments/lucas.yml
kubectl get pods,svc,pvc -n 344-group-project
Before applying for real, replace the Secret placeholders (or create the Secret separately), build/import astrowind:latest, and check whether port 53 is already occupied on the nodes.