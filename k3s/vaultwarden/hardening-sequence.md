# Vaultwarden deployment hardening: a staged learning path

This guide applies Vaultwarden-specific hardening to the active manifests under [`k3s/vaultwarden/`](./). It is designed to reduce the chance of locking yourself out or losing vault data: establish recovery first, make one change at a time, and verify each change before continuing.

It complements the older [scheduled image refresh guide](../../legacy/vw-security-path.md). That guide mainly hardens a Kubernetes Job which restarts Vaultwarden; it does not harden the Vaultwarden server process itself. Its paths and some statements no longer match this checkout. The active files are [`vw-app.yml`](vw-app.yml), [`vw-data.yml`](vw-data.yml), and the restart/RBAC resources in [`vw-force-rebuild.yml`](vw-force-rebuild.yml). The existing storage migration and update notes are in [`legacy/sequence.md`](../../legacy/sequence.md).

## What is already in place

| Control | Current state in this checkout | Next action |
| --- | --- | --- |
| Dedicated updater identity and scoped RBAC | `vw-force-rebuild.yml` defines `vw-restart-sa`, a namespace Role limited to `deployments/vw-app`, and a RoleBinding. | Verify the Job works and can do only its intended operation. Keep the Vaultwarden app's API token automount disabled. |
| Updater Job restrictions | It sets non-root IDs, drops capabilities, blocks privilege escalation, uses RuntimeDefault seccomp and a read-only root filesystem, and has resource limits. | Keep these Job controls. Do not assume they apply to the separate Vaultwarden Deployment. |
| App service account token | `vw-app.yml` sets `automountServiceAccountToken: false`. | Keep this. |
| Persistent data | The app mounts only `/data` from `vw-data-longhorn-pvc`; the PVC requests `ReadWriteOncePod`. | Make and restore-test an independent backup before changing ownership, storage, or image. Longhorn replicas are not backups. |
| Health checks and resources | The app has readiness `/alive`, liveness `/`, and CPU/memory requests and limits. | Preserve these; add a startup probe only if measured startup time calls for it. |
| Secret source | `run-deployments.yml` creates `vw-secret` from an Ansible Vault variable and suppresses task output. | Confirm the active deployment workflow still uses this protected secret path and that etcd/backups are protected. |
| Registration | `SIGNUPS_ALLOWED` is currently set to `true` by the Ansible task. | Decide when account creation should close, then change through the authoritative config source. |
| Image and app process | `vw-app.yml` uses `vaultwarden/server:latest`, `imagePullPolicy: Always`, no explicit security context, and the default HTTP port 80. | Prefer reviewed, digest-pinned releases; investigate non-root and high-port operation as a separate tested change. |
| Ingress | The manifest has an Ingress for `vaultwarden.home.arpa` and TLS secret `vw-tls-secret`. | Verify what Traefik exposes, that redirects/TLS work, and whether `/admin` should be restricted or disabled. |

## Ground rules for safe changes

- Treat the password vault data and its encryption keys as irreplaceable. Before every change that can alter data or startup behavior, make a backup and know how to restore it. `kennethpage@gideonihah-post-3 homelab-as-a-service % 344kctl -n 344-group-project cp vw-app-7bfdfc8b68-pc8qd:/data vw-bak`
- Use the repository's real apply path. The legacy security guide refers to `kenneth.yml`, but this checkout has `k3s/vaultwarden/*.yml`; `ansible/playbooks/run-deployments.yml` currently applies `k3s/deployments/kenneth.yml`. Reconcile this drift before relying on automation. Do not assume edits to `vw-app.yml` reach the cluster.
- For privileged cluster actions, use the intended administrative account and its `sudo`/`kubectl` path. First confirm the context and namespace. Do not give the Vaultwarden process host privileges, a privileged container, host mounts, or cluster credentials.
- Do not change the data PVC, database type, and image version in one maintenance. Avoid simultaneous storage migration and hardening work.
- Prefer source-controlled manifests and secret management. Never put an admin token or vault contents in shell history, command arguments, chat, logs, or an unencrypted file.
- Keep a maintenance window and console/SSH access to the cluster available. If health checks fail, roll back the last single manifest change and inspect logs/events before trying more changes.

## Sequence

### 1. Map the deployment and establish a recovery point

**Learn first:** [Kubernetes declarative object management](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/) explains desired versus live state, and the [`kubectl diff` reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_diff/) shows the exact comparison command; [Vaultwarden's backup guide](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault) describes what data to copy and recovery considerations.

1. Confirm the cluster, namespace, resources, and image actually running. Use read-only commands first, for example:

   ```sh
   kubectl config current-context
   kubectl -n 344-group-project get deploy,svc,ingress,pvc,pod
   kubectl -n 344-group-project get deploy vw-app -o yaml
   kubectl -n 344-group-project get pod -l app=vw-app -o wide
   ```

2. Compare live state with `k3s/vaultwarden/` and `ansible/playbooks/run-deployments.yml`. Identify which manifest is authoritative and correct the documentation/deployment path before making production changes. Check whether any additional cluster automation, Helm release, or manual patch owns these objects.
3. Back up the whole Vaultwarden data directory, including the SQLite database, attachments, Sends, and key/config files. Encrypt the backup, keep a copy off the Proxmox host, and verify the backup is readable. Rehearse a restore to an isolated location or test instance without overwriting production. Follow [Vaultwarden's backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault).
4. Record a rollback snapshot of the manifests and the currently running image digest, then check current user access and basic operations (login, sync, attachment/Sends if used, and any organization features). Do not proceed if a recovery path is uncertain.

### 2. Decide how the service should be reachable

**Learn first:** Vaultwarden's [Hardening Guide](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide#https--tls-configuration) explains HTTPS, reverse proxies, and strict SNI; its [HTTPS guide](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-HTTPS) covers proxy setup. [Traefik's Ingress documentation](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) explains how Kubernetes Ingress objects are routed.

1. Confirm whether Vaultwarden is LAN-only or intentionally reachable from the internet. Check DNS, router/firewall forwarding, Kubernetes Services, ingress controller configuration, and host firewall. The current `home.arpa` hostname suggests a local service, but the manifest alone cannot prove exposure.
2. Confirm clients use HTTPS with a valid certificate they trust. Vaultwarden's own hardening guidance recommends HTTPS and a reverse proxy; its admin page should not be enabled over an untrusted HTTP path. Test one client from the networks where it is expected to work.
3. Restrict access to `/admin` at Traefik/firewall if possible, or disable the admin page if you do not use it. Keep the admin token as a separate control even when network-restricted. Confirm WebSocket notifications and normal client traffic still work after any routing rule.
4. If public exposure is intentional, document that decision and add monitoring and abuse controls appropriate to the actual reverse-proxy path. Do not blindly install Fail2ban: it requires usable Vaultwarden logs, correct real-client-IP forwarding, and a ban mechanism at the layer receiving traffic. A misconfigured proxy header can make rate limits or bans ineffective or block the proxy itself.

### 3. Reduce application-level account and admin risk

**Learn first:** Vaultwarden's [Hardening Guide](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide#application-configuration) explains registration and password-hint settings; the focused [registration guide](https://github.com/dani-garcia/vaultwarden/wiki/Disable-registration-of-new-users) covers signup and invitation behavior. The [admin page guide](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page) explains token security, Argon2 hashing, sessions, and disabling `/admin`.

1. Decide whether anyone should be able to register. If the server is already provisioned for all intended users, change `SIGNUPS_ALLOWED` from `true` to `false` in the authoritative secret/config workflow, then apply and restart in a planned window. Verify existing users can still sign in and invited-user behavior is what you expect. Vaultwarden's [Hardening Guide](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide) recommends disabling open registration. Invitations can be restricted separately if you do not want users to invite others.
2. Review password hints, organization creation, invitations, emergency access, Sends, and other enabled features against actual use. Turn off only features you do not use, one setting at a time; validate clients and organization workflows after each change. In particular, `SHOW_PASSWORD_HINT` should remain false unless there is a deliberate reason to expose hints on the login page.
3. Check that `ADMIN_TOKEN` is long and randomly generated and is stored only in Ansible Vault/Kubernetes Secret. Prefer the Vaultwarden-supported Argon2 PHC representation for the configured token; follow the upstream [admin token guidance](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page#secure-the-admin_token). Plan token updates carefully: ensure your secret task does not print it, restart the app to load it, and verify admin login before closing the maintenance window.
4. If you do not need `/admin`, remove the token from all active config sources and data-directory `config.json`, and disable it according to the upstream instructions. Do not merely remove the Kubernetes Secret key while the persistent `config.json` may still override environment values. If you retain `/admin`, keep its network restriction and token.

### 4. Make image updates reviewable

**Learn first:** Kubernetes' [container image documentation](https://kubernetes.io/docs/concepts/containers/images/) explains tags, digests, and pull policies; [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment) explains rollout behavior and rollback limits. Review the upstream [Vaultwarden releases](https://github.com/dani-garcia/vaultwarden/releases) for version-specific changes before selecting a digest.

1. Replace the mutable `latest` reference with a reviewed version pinned by digest. Keep the previous digest and a verified data backup recorded for rollback. A digest improves repeatability; it does not make an unreviewed upgrade safe.
2. Update only the image pin in a maintenance change. Read release notes for migration/configuration changes, apply through the verified deployment path, wait for rollout readiness, then check logs and client login/sync. Because the app is one replica with `Recreate`, expect downtime during replacement.
3. Keep automatic update jobs from silently choosing new Vaultwarden code. The existing restart CronJob only restarts a pod; with a mutable `latest` tag it can deploy whatever is current at that time. Prefer a reviewed pin update, then schedule/perform the restart of that approved image.

### 5. Harden the Vaultwarden container in small, tested steps

**Learn first:** Vaultwarden's [container hardening notes](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide#docker-configuration) discuss the default root user, data mounts, and non-root operation. Kubernetes' [security context guide](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) explains user IDs, capabilities, seccomp, and read-only filesystems; the [Restricted Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted) is a reference checklist.

Vaultwarden's official image runs as root by default for simple data-directory permissions. Root inside this container is not the same as host root, but reducing the process UID is still useful defense in depth. The image also listens on port 80 by default. These settings interact with volume ownership and low-port binding, so do not add `runAsNonRoot: true` alone to the live Deployment.

1. Inspect the exact pinned image and its documented runtime user, writable paths, and port behavior. Check `/data` ownership and permissions without changing them. The data PVC must remain writable by Vaultwarden.
2. In a disposable test namespace with a copy of a recent backup, try a non-root UID/GID supported by the selected image. Confirm the process can read/write the database, attachments, Sends, and generated key files; restart the test pod and check the files again. Never test ownership changes against the production PVC.
3. If the image supports non-root operation, move the listener to a high port (for example 8080) and update `ROCKET_PORT`, the container port, Service `targetPort`, and HTTP probes together. This avoids needing `CAP_NET_BIND_SERVICE`. Confirm readiness, liveness, HTTPS ingress, and WebSocket/client behavior in the test instance.
4. Add `runAsNonRoot: true`, explicit `runAsUser`/`runAsGroup`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, and drop all capabilities in the app container after the test succeeds. Keep `automountServiceAccountToken: false`. Do not set `privileged`, host namespaces, or hostPath volumes.
5. Test `readOnlyRootFilesystem: true` separately. If the exact image needs temporary writes, provide only a small `emptyDir` for that path. Keep `/data` writable because Vaultwarden needs it. If any of these settings cause permission errors or crash loops, revert that setting and diagnose in the test instance.
6. Promote the tested settings to production as one small change. Use `kubectl diff`/review before apply, check events/logs and rollout status, then verify real clients and data operations. Retain the previous manifest and image digest for rollback.

Kubernetes' [Restricted Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted) is a useful checklist, but validate image compatibility before enforcing it on this workload.

### 6. Limit network paths without breaking required traffic

**Learn first:** Kubernetes' [NetworkPolicy guide](https://kubernetes.io/docs/concepts/services-networking/network-policies/) explains pod selectors, ingress/egress isolation, and why default-deny policies can block DNS; [Declare Network Policy](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/) walks through applying and checking a policy. Confirm support in the cluster's [K3s networking setup](https://docs.k3s.io/networking/basic-network-options).

1. Inventory traffic to/from the app: ingress from the Traefik controller, DNS if needed, any SMTP/push services in use, and the Kubernetes health-check path. Determine whether the installed CNI enforces Kubernetes NetworkPolicy; a policy object has no protective effect if the network plugin ignores it.
2. First add a narrow ingress allow rule for the actual Traefik pods/namespace and Vaultwarden port. Confirm client traffic, WebSockets, and probes still work.
3. Only after the ingress policy is proven, consider egress limits. Start with required DNS and explicitly used external services. Vaultwarden may fetch website icons or use push/email integrations depending on configuration; disabling those features or blocking egress can change client behavior. Test before enforcement.
4. Avoid applying a blanket default-deny policy to the whole shared namespace as the first change. Namespace-wide policies can affect unrelated workloads and make recovery confusing. Use labels that select only the Vaultwarden pod.

See the Kubernetes [NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/) and security checklist.

### 7. Protect secrets, backups, and access to the admin plane

**Learn first:** Kubernetes' [Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) explains Secret encryption and key-rotation risks; [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/) covers least privilege and service-account access. Vaultwarden's [backup guide](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault) and Longhorn's [backup scheduling guide](https://longhorn.io/docs/1.13.0/snapshots-and-backups/scheduling-backups-and-snapshots/) describe application data and storage backup options.

1. Verify the Kubernetes API Secrets are encrypted at rest in etcd, and that etcd snapshots, Ansible Vault files/password mechanisms, and Vaultwarden backups are protected and access-controlled. Kubernetes Secrets are base64-encoded objects by default, not encryption by themselves. See the Kubernetes [security checklist](https://kubernetes.io/docs/concepts/security/security-checklist/#secrets).
2. Keep the app and restart Job on separate ServiceAccounts: the app needs no Kubernetes API token, while the restart Job should retain only its scoped deployment permissions. Check the effective permissions and confirm the Job cannot read Secrets, PVCs, or unrelated deployments.
3. Ensure administrative kubeconfig access is restricted and backed up securely. Use the normal admin account and privilege escalation for cluster changes; do not mount kubeconfig, SSH keys, or host credentials into Vaultwarden.
4. Keep an independent backup schedule and occasionally rehearse recovery. Longhorn's three replicas improve storage availability but do not replace an off-host backup.

### 8. Observe, verify, and keep a rollback record

**Learn first:** Kubernetes' [readiness, liveness, and startup probe guide](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) explains what each health check means; [Deployment updates](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment) and [`kubectl rollout status`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_status/) explain how to observe an update and what rollout success confirms. Pair these checks with Vaultwarden's [backup and restore guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault).

After each production change, record the commit/image digest and the checks performed. Check deployment readiness, pod events, application logs, ingress TLS/routing, sign-in, vault sync, and any feature you disabled or depend on. Confirm the backup still exists and the previous configuration can be restored.

If the pod does not become ready, stop the sequence. Restore the last known-good manifest/image, inspect logs and events, and preserve the PVC. Do not delete/recreate the PVC, run recursive ownership changes on production data, or roll back across a database migration without first checking Vaultwarden's upgrade notes and restore plan.

## Completion checklist

- [ ] The active apply path and source of truth are known and match this repository.
- [ ] An encrypted, off-host backup has been restore-tested.
- [ ] Intended network exposure, HTTPS, and `/admin` access are documented and verified.
- [ ] New signups and other account features match the intended policy.
- [ ] The admin token is protected and Argon2-hashed, or the admin page is disabled.
- [ ] Vaultwarden releases are reviewed and pinned by digest.
- [ ] Non-root, high-port, seccomp, capability, and read-only-root settings have been validated against a test copy before production.
- [ ] NetworkPolicy support and required traffic are confirmed before policies are enforced.
- [ ] Kubernetes Secrets, etcd snapshots, Ansible credentials, and backups have appropriate encryption and access controls.
- [ ] Each production change has a verified health check and a known rollback.

## References

- [Legacy scheduled image refresh and updater Job guide](../../legacy/vw-security-path.md)
- [Vaultwarden Hardening Guide](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide)
- [Vaultwarden admin page and Argon2 token guidance](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page)
- [Vaultwarden backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)
- [Kubernetes Restricted Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- [Kubernetes Security Checklist](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
