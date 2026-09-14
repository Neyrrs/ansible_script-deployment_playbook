# Trend Vision One Windows Agent Deployment

This Ansible playbook deploys a portable Trend Vision One agent package on Windows hosts.

Create the package once with Client Packager on the Apex One/Vision One server. Store the resulting MSI or EXE in the controller; Ansible only transfers that single artifact and executes it on the endpoint.

## Requirements

- Ansible
- WinRM enabled on the Windows host
- Ansible collection `ansible.windows`
- A Windows account with Administrator rights
- A Client Packager MSI or EXE artifact

Install the required collection:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Configure the inventory

Edit `inventory/hosts.ini` and add your Windows host:

```ini
[vision_one_windows]
windows-home ansible_host=DESKTOP-PI6EBAV

[vision_one_windows:vars]
ansible_user=Administrator
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_port=5985
ansible_winrm_scheme=http
```

Do not store `ansible_password` in a plain text file. Use Ansible Vault or provide it with a secure secret-management method.

## Configure the package

Set the package source, destination, and silent arguments in:

```text
group_vars/vision_one_windows.yml
```

Default MSI values (the example below uses the artifact fetched to `/opt/apex-installer`):

```yaml
vision_one_package_src: "/opt/apex-installer/Agent_Installer.msi"
vision_one_package_dest: "C:\\Windows\\Temp\\VisionOneAgent.msi"
vision_one_package_arguments: "/qn /norestart"
```

For an EXE package, point `vision_one_package_src` and `vision_one_package_dest` to the EXE and replace `vision_one_package_arguments` with the silent switch defined when the package was generated. Do not deploy the raw `ofcscan` folder.

Keep the package private if it contains tenant information or activation data. Do not commit it to a public repository.

If the Windows host uses a proxy, set:

```yaml
vision_one_use_proxy: true
vision_one_proxy_url: "http://proxy.example.local:3128"
```

The proxy setting is used by Ansible when needed. The packaged installer must also contain the required proxy configuration if it needs one to reach Trend Micro.

## Run the playbook

Run the playbook from this directory:

```bash
ansible-playbook -i inventory/hosts.ini playbook.yml
```

If you use encrypted Ansible Vault variables, add:

```bash
ansible-playbook -i inventory/hosts.ini playbook.yml --ask-vault-pass
```

## What the playbook does

1. Checks whether the `tmlisten` and `ntrtscan` services are already running.
2. Skips installation when both services are already running.
3. Copies the single Client Packager artifact to the Windows host.
4. Runs the MSI/EXE with the configured silent arguments.
5. Removes the copied artifact, even when the installation fails.
6. Checks the services again after installation.

## Troubleshooting

- Check the Ansible output for WinRM connection errors.
- Make sure the Ansible user has Administrator rights.
- Make sure the Windows host can access Trend Micro endpoints.
- Check the Trend Micro log at:

```text
%APPDATA%\Trend Micro\V1ES\v1es_install.log
```

- Check the `EndpointBasecamp.log` file if agent registration fails.
