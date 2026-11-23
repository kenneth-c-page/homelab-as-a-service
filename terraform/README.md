# Terraform

## Longhorn worker data disks (TODO)

Terraform currently configures the Proxmox provider but does not provision the additional data disks for the k3s workers. Add a dedicated virtual disk to each of `worker1`, `worker2`, and `worker3`, keeping each worker's OS disk separate.

- [ ] Confirm the Proxmox storage target has room for the disks and supports VM disk images. Size each disk for at least the planned 10 Gi Vaultwarden volume plus room for snapshots and growth; each worker stores a full Longhorn replica.
- [ ] Add the disks to the worker VMs through Terraform and keep their configuration separate from the OS disks.
- [ ] Document/apply the handoff to Ansible, which will format and mount each disk inside the guest by filesystem UUID, then register and tag it in Longhorn. Terraform attachment alone does not format or mount a guest filesystem.

See [`ansible/README.md`](../ansible/README.md) for worker disk preparation and Longhorn node/disk registration and tags. See [`k3s/deployments/kenneth/sequence.md`](../k3s/deployments/kenneth/sequence.md) for the Vaultwarden PVC creation, data migration, workload switch, and old NFS PVC/PV cleanup steps.
