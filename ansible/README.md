Edit the password vault file with

ansible-vault edit inventory/group_vars/nodes/vault.yml

The password protecting it is the same as the nodes' user passwords for this project

To use the password, run ansible-playbook playbooks/<playbook>.yml --ask-vault-pass. Run this from the ansible/ directory so it pulls ansible.cfg. If you depend on a hosts file at a position other than where hosts.ini is, specify that path when you run.

The Proxmox node's root password is kept in a separate vault, since it differs from the nodes' password. Create it once with

ansible-vault create --vault-id proxmox@prompt inventory/group_vars/proxmox/vault.yml

and put this line in it:

vault_proxmox_root_password: <proxmox root password>

Edit it later with ansible-vault edit --vault-id proxmox@prompt inventory/group_vars/proxmox/vault.yml. Playbooks that touch the Proxmox node (init-storage.yml) need both vault passwords:

ansible-playbook playbooks/init-storage.yml --vault-id nodes@prompt --vault-id proxmox@prompt

You'll need to install sshpass to get this setup to work. See more [here](https://oneuptime.com/blog/post/2026-02-21-how-to-use-ansible-with-password-based-ssh-authentication/view)

If you're running a distro that doesn't come with sudo installed (which Ansible attempts to use by default) or python, run init-debian-targets.yml for debian-like targets, and modify as necessary per your distro.

Some connections will fail arbitrarily, just try running commands again as needed

To add Longhorn block storage, run init-longhorn.yml after k3s-clustering.yml:

ansible-playbook playbooks/init-longhorn.yml --ask-vault-pass

It checks the cluster's Kubernetes version against the Longhorn release pinned in playbooks/vars/longhorn.yml, installs the node prerequisites (open-iscsi with iscsid running, nfs-common, cryptsetup, dmsetup), installs Longhorn, and makes `longhorn` the default StorageClass. Before bumping `longhorn_version`, check the new release's Kubernetes requirement and update `longhorn_min_kubernetes_version` to match.

After running the k3s/run-deployments playbook, to see what nodes are running, run kubectl --kubeconfig /path/to/k3s_config get nodes
## Longhorn worker data disks (TODO)

The existing `init-longhorn.yml` installs Longhorn and its host prerequisites, but it does not prepare the extra worker disks or configure Longhorn to use them. After Terraform attaches a dedicated virtual disk to each worker (see [`terraform/README.md`](../terraform/README.md)):

- [ ] On `worker1`, `worker2`, and `worker3`, identify each new disk with `lsblk -f`; verify the device and size before formatting so the OS or existing data disk is not touched.
- [ ] Format each new disk with ext4 or XFS, mount it at `/mnt/longhorn-data`, and persist the mount by UUID in `/etc/fstab`. Automate this in Ansible so it survives rebuilds and remains repeatable.
- [ ] Register `/mnt/longhorn-data` as a schedulable filesystem disk in each worker's Longhorn node configuration.
- [ ] Add the `vw-storage` Longhorn node tag to each worker and the `vw-data` disk tag to each registered disk. Do not tag the master for this placement.
- [ ] Verify all three disks are schedulable and have enough capacity for one full replica each before creating the Vaultwarden claim.

The Vaultwarden-specific StorageClass, data migration, workload switch, and old NFS PVC/PV cleanup are tracked in [`k3s/deployments/kenneth/sequence.md`](../k3s/deployments/kenneth/sequence.md). Keep the old claim and PV until the Longhorn copy is verified and Vaultwarden is confirmed working; deleting storage may permanently delete its data depending on the reclaim policy.
