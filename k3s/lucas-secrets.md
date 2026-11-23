# Secrets for Lucas's services

The tracked manifest no longer contains the `homelab-secrets` Secret.
`k3s/secrets.example.yml` is the template; create the real Secret separately so
applying `k3s/deployments/lucas.yml` can never overwrite it with placeholders.

On the existing cluster `homelab-secrets` already exists. Leave it alone unless
you are intentionally rotating a value.

## Values used

| Key | Used by | Notes |
| --- | --- | --- |
| `PG_PASS` | PostgreSQL and Authentik | Used as PostgreSQL's `POSTGRES_PASSWORD` and Authentik's `AUTHENTIK_POSTGRESQL__PASSWORD`. PostgreSQL does not accept passwords longer than 99 characters. |
| `AUTHENTIK_SECRET_KEY` | Authentik server and worker | Must be identical for both Deployments. Changing it after the first start can invalidate sessions and encrypted data. |
| `PIHOLE_PASSWORD` | Pi-hole | Admin/API password for the Pi-hole web UI. |

## Generate values

Run these in a terminal (WSL/Linux/macOS):

```bash
openssl rand -base64 36 | tr -d '\n'   # PG_PASS
openssl rand -base64 60 | tr -d '\n'   # AUTHENTIK_SECRET_KEY
openssl rand -base64 24 | tr -d '\n'   # PIHOLE_PASSWORD
```

Use a password manager or a password of your choice for the Pi-hole value.

## Create the Secret

### Option A: local file from the example (recommended for a fresh cluster)

`k3s/secrets.local.yml` is ignored by Git.

```bash
cp k3s/secrets.example.yml k3s/secrets.local.yml
# edit k3s/secrets.local.yml and replace the three placeholders
kubectl apply -f k3s/secrets.local.yml
```

### Option B: create it directly

```bash
kubectl create secret generic homelab-secrets \
  -n 344-group-project \
  --from-literal=PG_PASS="$(openssl rand -base64 36 | tr -d '\n')" \
  --from-literal=AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')" \
  --from-literal=PIHOLE_PASSWORD='choose-a-strong-password' \
  --dry-run=client -o yaml > /tmp/homelab-secrets.yaml

kubectl apply -f /tmp/homelab-secrets.yaml -n 344-group-project
```

For a GitOps workflow, use a tool such as Sealed Secrets, SOPS, or External
Secrets instead of committing plaintext.

Do not apply `k3s/secrets.example.yml` as-is. If the Secret already exists, that
would replace the real values with placeholders.

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
  kubectl rollout restart \
    deployment/authentik-server \
    deployment/authentik-worker \
    deployment/authentik-postgresql \
    deployment/pihole \
    -n 344-group-project
  ```

## Apply order

For a fresh cluster:

```bash
kubectl apply -f k3s/namespace.yml
kubectl apply -f k3s/secrets.local.yml
kubectl apply -f k3s/deployments/lucas.yml
```

On the existing cluster, the Secret is already present, so skip the second
command. See [lucas-deploy.md](lucas-deploy.md) for the authentik server/worker
migration and validation steps.

## Verify

```bash
kubectl get secret homelab-secrets -n 344-group-project
kubectl describe secret homelab-secrets -n 344-group-project
```

The values are not printed by `describe`; use `-o yaml` only when you really
need to inspect them.
