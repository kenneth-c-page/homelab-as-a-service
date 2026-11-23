# Vaultwarden scheduled image refresh with a scoped Kubernetes CronJob

This guide documents the mutable-tag approach: Vaultwarden uses `vaultwarden/server:latest` with `imagePullPolicy: Always`, and a weekly in-cluster CronJob restarts the Deployment so Kubernetes resolves the tag again when the replacement pod starts.

The current [`kenneth.yml`](../kenneth.yml) pins Vaultwarden by digest. Restarting that digest will not fetch a newer release. This guide's mutable-tag policy differs from Step 8 of [`sequence.md`](sequence.md), which recommends deploying an approved pinned version. Choose one policy and keep the manifest, scheduled updater, and documentation consistent. Kubernetes recommends meaningful tags or digests for traceability and rollback; `latest` trades that control for unattended updates. [Kubernetes image documentation](https://kubernetes.io/docs/concepts/containers/images/)

Vaultwarden currently has one replica, uses SQLite on a persistent claim, and uses the `Recreate` Deployment strategy. Replacing its pod causes downtime while the new pod starts. Keep a recoverable backup before enabling unattended upgrades. [Deployment strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) · [Vaultwarden backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)

## Source-led implementation steps

### 1. Decide and record the image update policy

Use the Kubernetes image documentation to compare mutable tags, pull policies, and digests. For this guide's scheduled refresh, select `vaultwarden/server:latest` and explicitly set `imagePullPolicy: Always` on the `vw-pod` container. A restarted pod then asks the registry to resolve the tag at startup. Merely restarting the current digest does not update it. [Images](https://kubernetes.io/docs/concepts/containers/images/)

Keep Vaultwarden's data volume, probes, resource limits, and existing `Recreate` strategy intact while making this image-only change. Use the Deployment documentation to understand the replacement behavior and the expected short interruption. [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

### 2. Create a dedicated ServiceAccount and namespace-scoped RBAC

Follow the Kubernetes RBAC guide to create a ServiceAccount, a Role in namespace `344-group-project`, and a RoleBinding for that ServiceAccount. Avoid the default ServiceAccount and avoid a ClusterRoleBinding. Scope the Role to the `deployments` resource named `vw-app`; grant only the verbs needed to restart and observe that Deployment (typically `patch`, `get`, and `watch`). Do not grant access to Secrets, Pods, or other workloads. Check the exact API requests used by the chosen kubectl commands with `kubectl auth can-i` before enabling the schedule. [RBAC authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) · [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)

The Job must authenticate to the Kubernetes API, so give it this dedicated ServiceAccount and allow its projected API token to be mounted. Do not copy a cluster-admin kubeconfig into the Job. Kubernetes documents ServiceAccount token mounting and how to disable it for workloads that do not need API access. [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

### 3. Define the CronJob's restart and completion behavior

Use the Kubernetes CronJob walkthrough to create a CronJob in `344-group-project`. Its container should run `kubectl rollout restart deployment/vw-app -n 344-group-project`, followed by `kubectl rollout status deployment/vw-app -n 344-group-project --timeout=300s`. The first command changes the Deployment pod template and starts a new rollout; the second makes the Job fail if the replacement does not become ready in time. Match the kubectl client minor version to the cluster's supported version skew. Pin the kubectl container image by digest after selecting a trusted publisher. [CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) · [kubectl rollout restart](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_restart/) · [kubectl rollout status](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_status/) · [Version skew policy](https://kubernetes.io/releases/version-skew-policy/) · [Kubernetes image documentation](https://kubernetes.io/docs/concepts/containers/images/)

Choose a low-traffic weekly schedule and set an explicit time zone supported by the cluster. Set `concurrencyPolicy: Forbid`, a reasonable `startingDeadlineSeconds`, bounded retries and runtime, and small successful/failed Job history limits. Kubernetes documents these fields and their scheduling behavior. [CronJob scheduling, time zones, concurrency, and history](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)

### 4. Harden the Job pod

Apply the Kubernetes application security checklist and security-context documentation to the kubectl container: run as non-root, use the RuntimeDefault seccomp profile, drop all Linux capabilities, set `allowPrivilegeEscalation: false`, and use a read-only root filesystem if the chosen image supports it. Set CPU and memory requests/limits, do not use privileged mode or host namespaces, and do not mount Vaultwarden's data PVC or its Secret. [Application security checklist](https://kubernetes.io/docs/concepts/security/application-security-checklist/) · [Pod and container security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) · [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

Use the restricted Pod Security Standard as a checklist for the Job's pod fields. Test the exact kubectl image with the selected restrictions; if it needs a writable temporary directory, add only a small `emptyDir` mounted at that path rather than making the root filesystem writable. [Pod Security Standards: Restricted](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)

### 5. Add the resources to the repository's deployment path

The existing Ansible playbook applies `k3s/deployments/kenneth.yml` and refreshes the Vaultwarden Secret from Ansible Vault. Add the ServiceAccount, Role, RoleBinding, and CronJob manifests to that managed file as additional YAML documents, or add an explicit apply task for a separate manifest. Keep the existing Secret handling unchanged. Review the Ansible playbook and its Vault password guidance before scheduling any controller-side alternative. [Repository playbook](../../../../ansible/playbooks/run-deployments.yml) · [Ansible Vault password management](https://docs.ansible.com/ansible/latest/vault_guide/vault_managing_passwords.html)

Keep the CronJob definition in source control. Do not let a scheduled command silently mutate the image field independently of the declared manifest: in this design the manifest intentionally declares `latest`, and the scheduled command only triggers a new pod to resolve that tag.

### 6. Validate permissions and run one controlled update

Before enabling the recurring schedule, use Kubernetes' authorization check to confirm the Job ServiceAccount can patch, get, and watch only `deployments/vw-app` in `344-group-project`, and cannot read Secrets or modify other resources. [kubectl auth can-i](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/) · [RBAC resource names](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#referring-to-resources)

Create a one-off Job from the CronJob template and inspect its completion state and logs. Confirm that a new Vaultwarden pod becomes ready, the running image ID has been resolved from the registry, and normal login and sync work after the restart. Kubernetes documents how to create a Job from a CronJob and inspect Jobs. [Create a Job from a CronJob](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_job/) · [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

Only then enable the weekly schedule. Since `latest` can change without a source-control diff, retain backups and watch Job failures and Vaultwarden readiness after each scheduled run. If you need a clear version history or reliable image rollback, return to a pinned digest and update it through a reviewed manifest change instead. [Kubernetes image documentation](https://kubernetes.io/docs/concepts/containers/images/) · [Vaultwarden backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)

## Completion checklist

- [ ] `vw-app` explicitly uses `vaultwarden/server:latest` and `imagePullPolicy: Always`.
- [ ] The Vaultwarden data PVC and Secret are not mounted into the updater Job.
- [ ] The updater uses a dedicated ServiceAccount and namespace-scoped Role/RoleBinding with only the needed access to `vw-app`.
- [ ] The kubectl image is trusted, digest-pinned, and compatible with the cluster's Kubernetes version.
- [ ] The CronJob has an explicit schedule/time zone, `Forbid` concurrency, bounded runtime/retries, and limited Job history.
- [ ] The Job pod uses restricted security settings and has no unnecessary volumes, privileges, or credentials.
- [ ] A manually triggered Job completed successfully, the new pod became ready, and Vaultwarden was verified.
- [ ] A current, restorable backup exists before unattended updates are enabled.
