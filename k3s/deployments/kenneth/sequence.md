# Vaultwarden: migrate NFS data to Longhorn and use scheduled Recreate updates

This sequence changes Vaultwarden from its current NFS-backed SQLite volume to a Longhorn block volume whose three replicas are placed on the three k3s worker nodes. It keeps one Vaultwarden pod and accepts a short outage during data migration and planned image updates.

## Current repo state

- [`deployments/kenneth.yml`](deployments/kenneth.yml) has one Vaultwarden replica and a static 10 Gi NFS PV/PVC (`vw-data-pvc`). Vaultwarden defaults to SQLite because no `DATABASE_URL` is configured. The image is `vaultwarden/server:latest`.
- The manifest already has readiness at `/alive` and liveness at `/`. Keep readiness at `/alive`; that endpoint checks the database connection. Keep liveness separate so a database outage does not trigger repeated app restarts. [Kubernetes probe guidance](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) · [Vaultwarden `/alive` implementation](https://github.com/dani-garcia/vaultwarden/blob/main/src/api/web.rs)
- [`ansible/playbooks/init-longhorn.yml`](../ansible/playbooks/init-longhorn.yml) installs Longhorn, checks the cluster version, prepares iSCSI prerequisites on the master and workers, and makes Longhorn the default StorageClass. [`vars/longhorn.yml`](../ansible/playbooks/vars/longhorn.yml) pins Longhorn `v1.13.0` and requires Kubernetes `1.34` or later.
- Longhorn is not yet configured here to use extra disks on the workers. Its default V1 disk path is `/var/lib/longhorn`, which would use each node's root disk unless additional disks are mounted and registered.
- [`run-deployments.yml`](../ansible/playbooks/run-deployments.yml) applies `kenneth.yml` and manages the Vaultwarden Secret, but does not wait for Vaultwarden's rollout to complete.
- In [`inventory/hosts.ini`](../ansible/inventory/hosts.ini), `worker1`, `worker2`, and `worker3` are the k3s workers. `storage0` currently serves NFS and is not joined to k3s by [`k3s-clustering.yml`](../ansible/playbooks/k3s-clustering.yml).

## Target design and terminology

- Vaultwarden remains at `replicas: 1` and uses SQLite on a single-pod Longhorn PVC. A `Recreate` Deployment strategy stops the old pod before starting its replacement, so planned updates involve downtime and do not run two Vaultwarden processes against the same database.
- The PVC will use Longhorn's CSI block volume with `ReadWriteOncePod` and `volumeMode: Filesystem`. “Block volume” here describes the Longhorn CSI volume presented to the pod. Longhorn's default V1 data engine stores its replicas on filesystem disks mounted on the worker nodes; the worker disks should be formatted with ext4 or XFS. Do not use Longhorn's separate V2 `diskType: block` setting for this V1 setup. [Longhorn disk types and setup](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/multidisk/) · [Longhorn volume access modes](https://longhorn.io/docs/1.13.0/nodes-and-volumes/volumes/create-volumes/)
- A custom StorageClass will select the three workers and request three replicas. Longhorn keeps a full copy on each eligible worker; this is storage redundancy, not a backup. The three worker VMs currently run under one Proxmox host, so Longhorn replicas do not protect against that host or its underlying storage failing.

## Sequence

### 1. Confirm versions and make a recoverable backup

1. Check the cluster version with `kubectl version`. The existing Longhorn playbook checks it against the pinned minimum in `vars/longhorn.yml`; upgrade k3s or choose a compatible Longhorn release if the check fails. Longhorn's K3s instructions also list host prerequisites such as `open-iscsi`/`iscsiadm`. [Longhorn installation requirements](https://longhorn.io/docs/1.13.0/deploy/install/#installation-requirements) · [Longhorn CSI on K3s](https://longhorn.io/docs/1.13.0/advanced-resources/os-distro-specific/csi-on-k3s/)
2. Make and verify a separate backup of Vaultwarden data before changing storage. Include the SQLite database and the data directory's attachments, Sends, and key/config files. A PVC or Longhorn replica is not a backup. Store a copy outside the Proxmox host if possible. [Vaultwarden backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)
3. Record the image currently running before replacing `latest`. Inspect the pod's image ID and pin that exact image digest in `kenneth.yml` for the storage migration. Do not combine the storage migration with a Vaultwarden version upgrade; keep one variable changing at a time. [Kubernetes image behavior](https://kubernetes.io/docs/concepts/containers/images/)

### 2. Add a virtual disk to each worker from Proxmox LVM-thin

1. In Proxmox, confirm which LVM-thin storage has free capacity and permits VM disk images (often named `local-lvm`, but verify in **Datacenter → Storage**). Create an additional SCSI virtual disk for each of `worker1`, `worker2`, and `worker3` using that storage. Keep the worker OS disk separate.
2. Size each extra disk for at least the Vaultwarden volume's requested 10 Gi plus headroom for snapshots and growth. Longhorn's replica count is three, so each worker needs room for its own full replica. Monitor both LVM-thin data and metadata usage; virtual disks can be thin-provisioned beyond the pool's physical capacity.
3. Do not use the ZFS pools currently handed to `storage0` by `init-storage.yml` as Proxmox VM storage at the same time. Those pools are owned/imported by the storage VM and exported over NFS. Reusing them would require a deliberate storage ownership migration first. [Proxmox VE storage guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf)

All three worker VMs appear to reside on the same Proxmox host. The Longhorn copies can protect against a worker VM failure, but a failure of that single Proxmox host can still make all three copies unavailable. For host-level resilience, storage replicas must span independent physical hosts; backups should also be stored independently.

### 3. Format and mount the new disks inside the workers

1. On each worker, identify the newly attached disk with `lsblk -f` and verify its size/device carefully. Do not format the OS disk or any existing data disk.
2. Format only the new disk with ext4, create a dedicated mount point such as `/mnt/longhorn-data`, and mount the filesystem there. Use the filesystem UUID in `/etc/fstab` so it is mounted again after a reboot. Longhorn's V1 engine uses filesystem disks mounted on the node. [Longhorn filesystem disk setup](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/multidisk/)
3. For repeatability, add the disk preparation and persistent mount to an Ansible playbook rather than relying on undocumented manual changes. The existing `init-longhorn.yml` installs Longhorn prerequisites, but it does not partition, format, or mount these extra worker disks.

### 4. Register the three worker disks with Longhorn

1. Run the existing Longhorn playbook from `ansible/` if it has not already been applied:

   ```sh
   ansible-playbook playbooks/init-longhorn.yml --ask-vault-pass
   ```

   It installs Longhorn `v1.13.0` according to `playbooks/vars/longhorn.yml`, checks the Kubernetes version, and prepares `master_node` and `workers` for Longhorn.
2. For each worker, register `/mnt/longhorn-data` as a schedulable filesystem disk in the Longhorn UI (**Nodes → select node → Edit Disks**) or with `kubectl edit node.longhorn.io <node-name>`. In the node resource's `spec.disks`, set the disk path to the mounted directory and `diskType: filesystem`. These are alternative ways to register the mount; the disk must already be formatted and mounted first.
3. Add a Longhorn node tag such as `vw-storage` to each worker and a disk tag such as `vw-data` to each new disk. Do not add those tags to the master. Longhorn StorageClass node/disk selectors use these tags to constrain replica placement. [Longhorn storage tags](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/storage-tags/)
4. Confirm all three worker disks are schedulable and have sufficient free capacity before creating the Vaultwarden PVC. Longhorn preserves complete replicas and schedules them across eligible nodes. [Longhorn scheduling](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/scheduling/)

### 5. Create a Vaultwarden-specific StorageClass and PVC

Create a custom StorageClass instead of relying on a cluster-wide default. This avoids changing Longhorn's default class and makes Vaultwarden's three-worker placement explicit. The example below assumes the tags from the previous step:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vw-longhorn
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  fsType: "ext4"
  nodeSelector: "vw-storage"
  diskSelector: "vw-data"
  replicaSoftAntiAffinity: "disabled"
```

`numberOfReplicas: "3"` requests three full copies. The node selector limits them to the tagged workers; disabling replica node soft anti-affinity prevents Longhorn from placing multiple healthy replicas of this volume on the same node. The PVC should use this class explicitly. [Longhorn StorageClass parameters](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/) · [Storage tags](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/storage-tags/)

Create a new PVC, for example `vw-data-longhorn-pvc`, rather than trying to change the existing statically bound NFS claim in place:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vw-data-longhorn-pvc
  namespace: 344-group-project
spec:
  accessModes:
    - ReadWriteOncePod
  volumeMode: Filesystem
  storageClassName: vw-longhorn
  resources:
    requests:
      storage: 10Gi
```

`ReadWriteOncePod` restricts this claim to one pod across the cluster. Confirm support in the Kubernetes and Longhorn CSI versions installed. If it is not supported, use `ReadWriteOnce` while retaining one Vaultwarden replica and `Recreate`; RWO alone does not prevent two pods on the same node from mounting the volume. [Kubernetes PV access modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) · [Longhorn volume access modes](https://longhorn.io/docs/1.13.0/nodes-and-volumes/volumes/create-volumes/)

### 6. Copy Vaultwarden data during a maintenance window

1. Schedule downtime. Scale `vw-app` to zero and wait until the Vaultwarden pod has terminated. This stops writes to SQLite while the data directory is copied.
2. Wait for the new Longhorn PVC to bind and verify Longhorn reports three healthy replicas, one on each worker.
3. Run a one-off migration pod or Job in `344-group-project` that mounts the old `vw-data-pvc` read-only at `/source` and the new claim read-write at `/target`. Copy the complete directory, preserving ownership and attributes; for example:

   ```sh
   tar -C /source -cpf - . | tar -C /target -xpf -
   ```

4. Compare the source and destination contents and confirm the database, attachments, Sends, and key files are present. Delete the migration pod so it releases the `ReadWriteOncePod` claim before starting Vaultwarden.
5. Keep the old NFS PV/PVC intact and do not reuse its data directory. It is a fallback copy, but it will become stale as soon as Vaultwarden writes to Longhorn.

### 7. Switch Vaultwarden to the Longhorn claim

Update `deployments/kenneth.yml`:

- Keep `replicas: 1`.
- Set `strategy.type: Recreate`.
- Change the pod volume's `claimName` to `vw-data-longhorn-pvc`.
- Use the pinned image digest recorded in Step 1.
- Keep readiness on `/alive` and liveness separate.

Apply the updated manifest and wait for the pod to become ready. Test login, vault sync, attachment/Sends access, and recovery from a pod restart. Confirm the Longhorn volume shows three healthy replicas placed across `worker1`, `worker2`, and `worker3`. `Recreate` causes downtime during pod replacement by design. [Kubernetes Deployment strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) · [Vaultwarden backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)

### 8. Schedule deployment of approved, pinned versions

Keep the desired Vaultwarden image pin in version-controlled `deployments/kenneth.yml`. For each upgrade, review and change that pin before the maintenance window; do not have the job silently switch to `latest`. The scheduled task should deploy the approved pin. It should not independently patch the Deployment to a different image than the repo specifies.

The existing `run-deployments.yml` already applies `kenneth.yml`, but also installs/waits for cert-manager and creates the Vaultwarden Secret. For a scheduled update, either schedule that playbook or create a smaller dedicated Ansible playbook that applies the namespace/Secret as needed, applies `kenneth.yml`, and waits for rollout completion. Add a task equivalent to:

```sh
kubectl -n 344-group-project rollout status deployment/vw-app --timeout=300s
```

Run the playbook on the Ansible controller during the maintenance window. An unattended scheduler cannot answer `--ask-vault-pass`; configure a protected Ansible Vault password file or password-client mechanism with permissions limited to the scheduler account. [Ansible Vault password management](https://docs.ansible.com/ansible/latest/vault_guide/vault_managing_passwords.html) · [Kubernetes rollout status and rollback](https://kubernetes.io/docs/tasks/run-application/update-deployment-rolling/)

Because the Deployment uses `Recreate`, an image change stops the old pod before starting the new one. The Service has no ready Vaultwarden endpoint during that interval. A failed rollout should be reported by the job; restore the previous image only if its database schema remains compatible. Keep a pre-update backup because rolling back a container image does not roll back database changes.

### 9. Retire the NFS claim only after validation

After successful migration, backup, restore rehearsal, and at least one planned update, remove the unused NFS PV/PVC definitions from the active Vaultwarden manifest in a separate cleanup change. Follow the PV's `Retain` policy and deliberately archive or delete the old NFS data only after confirming it is no longer needed. Longhorn recurring backups should target storage independent of the Proxmox host; volume replicas and local snapshots alone do not protect against loss of that host. [Kubernetes PV reclaim policies](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming) · [Longhorn recurring backups](https://longhorn.io/docs/1.13.0/snapshots-and-backups/scheduling-backups-and-snapshots/) · [Vaultwarden backup guidance](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)

## Completion checklist

- [ ] Longhorn version is supported by the cluster, and its prerequisites are installed on the k3s nodes.
- [ ] Each of worker1–3 has a dedicated Proxmox virtual disk, formatted/mounted inside the guest, and registered as a schedulable Longhorn filesystem disk.
- [ ] Vaultwarden's StorageClass selects only those three workers and requests three replicas; the volume reports three healthy replicas on distinct workers.
- [ ] A verified backup exists outside the Proxmox host.
- [ ] Vaultwarden uses the new Longhorn PVC, one replica, `Recreate`, a pinned image, and readiness on `/alive`.
- [ ] The scheduled Ansible deployment applies the approved pin, waits for rollout status, and reports failures.
- [ ] The NFS source is retained until migration and recovery have been verified.
