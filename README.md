# Trend Vision One Windows AutoPcc Deployment

This Ansible playbook currently deploys the Trend Vision One agent on Windows endpoints by connecting to an SMB share and running the `AutoPcc.exe` installation flow from the share.

The current setup does not copy an MSI/EXE artifact from the controller to the remote host. Instead, the playbook uses a UNC path such as `\\10.100.33.116\ofcscan`, maps it with `net use`, and then runs the deployment script from that share.

## Requirements

- Ansible
- WinRM enabled on the Windows host
- Ansible collection `ansible.windows`
- A Windows account with Administrator rights
- Access to the Apex One / Vision One share (`\\server\share`)
- Valid credentials stored in Ansible Vault

Install the required collection:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Inventory

Current inventory is configured like this:

```ini
[apex_one_windows]
windows-home1 ansible_host=10.100.36.147
windows-home2 ansible_host=10.100.36.148

[apex_one_windows:vars]
ansible_user=Administrator
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_port=5985
ansible_winrm_scheme=http
ansible_password=P@ssw0rd
```

Do not keep sensitive credentials in plain text when possible. In this project, the share user and password are stored in the vault file under `group_vars/apex_one_windows/vault.yml`.

## Variables

The relevant values are stored in `group_vars/apex_one_windows/vars.yml`:

```yaml
apex_one_share: '\\10.100.33.116\ofcscan'
apex_one_share_user: "{{ vault_apex_one_share_user }}"
apex_one_share_password: "{{ vault_apex_one_share_password }}"
apex_one_connection_debug: true
ansible_winrm_operation_timeout_sec: 600
ansible_winrm_read_timeout_sec: 660
```

This timeout setup is intentional because WinRM `ntlm` requires `read_timeout_sec` to be greater than `operation_timeout_sec` and both values must be non-zero.

## Run the playbook

From this directory:

```bash
ansible-playbook playbook.yml
```

If vault variables are encrypted:

```bash
ansible-playbook playbook.yml --ask-vault-pass
```

## What the playbook does

1. Connects to the Apex One share via `net use` on the remote Windows host.
2. Uses the configured share credentials to authenticate to the network location.
3. Executes the `AutoPcc` deployment workflow from the mounted share.
4. Fails immediately if the share cannot be reached or the UNC path is invalid.

## Known deployment behavior

The current automation is sensitive to SMB/network availability. If the network share is unreachable, the task fails with errors such as:

```text
System error 67 has occurred.
The network name cannot be found.
```

This usually means one of the following:

- the UNC path is wrong
- the Windows host cannot reach `10.100.33.116`
- SMB port `445` is blocked or filtered
- the share does not exist
- the provided account lacks permission to access the share

## Troubleshooting

Check these from the Windows endpoint:

```powershell
Test-NetConnection 10.100.33.116 -Port 445
dir \\10.100.33.116\ofcscan
net use \\10.100.33.116\ofcscan /user:Administrator P@ssw0rd
```

If the `net use` command fails, fix the SMB path, firewall, or credential issue before re-running the playbook.

Also verify the WinRM connectivity:

```powershell
winrm quickconfig
```

If `winrm` is not properly configured, Ansible cannot reach the Windows host even though the SMB share may be valid.

## Notes

- This project is currently tuned for a share-based deployment model, not a local MSI package deployment model.
- The share must be reachable from every target Windows host.
- Use Ansible Vault for credentials and keep them out of the repository when possible.
