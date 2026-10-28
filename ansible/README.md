Edit the password vault file with

ansible-vault edit inventory/group_vars/nodes/vault.yml

The password protecting it is the same as the nodes' user passwords for this project

To use the password, run ansible-playbook playbooks/<playbook>.yml --ask-vault-pass. Run this from the ansible/ directory so it pulls ansible.cfg

You'll need to install sshpass to get this setup to work. See more [here](https://oneuptime.com/blog/post/2026-02-21-how-to-use-ansible-with-password-based-ssh-authentication/view)

If you're running a distro that doesn't come with sudo installed (which Ansible attempts to use by default) or python, run init-debian-targets.yml for debian-like targets, and modify as necessary per your distro.

Some connections will fail arbitrarily, just try running commands again as needed

After running the k3s playbook, to see what 