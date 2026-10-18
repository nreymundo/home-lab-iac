# Ansible secrets

## AudioMuse-AI

`audiomuse.sops.yml` is committed encrypted and contains the internal PostgreSQL password and stable JWT signing secret used by the AudioMuse-AI container role. The AudioMuse administrator credentials and media-server credentials are configured through the application's setup wizard and stored in PostgreSQL.

Verify the encrypted file without printing its contents:

```bash
sops --decrypt ansible/secrets/audiomuse.sops.yml >/dev/null
```

## NetBird

`netbird.sops.yml` is committed encrypted. SOPS encrypts all `netbird_*` values
using the repository Age recipient:

```yaml
netbird_fqdn: netbird.example.com
netbird_acme_email: admin@example.com
netbird_owner_email: admin@example.com
netbird_owner_name: NetBird Owner
netbird_owner_password: replace-with-a-long-random-password
netbird_mesh_proxy_setup_key: replace-with-the-one-time-netbird-setup-key
```

Edit and encrypt the file with:

```bash
sops ansible/secrets/netbird.sops.yml
```

The Ansible control host needs `sops` and access to the matching Age private key.
The role defaults to `~/.config/sops/age/keys.txt`; override it with
`SOPS_AGE_KEY_FILE` when the identity is stored elsewhere.

The mesh proxy setup key is consumed during initial enrollment. Its persistent
Docker volume preserves the peer identity. If that volume is lost, create a new
setup key for `netbird-proxy`, replace the encrypted value, and rerun the
NetBird playbook.

## Proxmox

`proxmox.sops.yml` holds the SMTP credentials for the Proxmox email
notification target. Edit the encrypted document with SOPS and verify that it
can be decrypted without printing its contents:

```bash
sops ansible/secrets/proxmox.sops.yml
sops --decrypt ansible/secrets/proxmox.sops.yml >/dev/null
```

Contents:

```yaml
proxmox_smtp_username: <SMTP login user>
proxmox_smtp_password: <SMTP login password>
proxmox_smtp_from_address: <envelope From address>
proxmox_smtp_recipients:
  - <alert recipient>
proxmox_smtp_credential_revision: <any short value, e.g. 1>
```

`proxmox_smtp_credential_revision` is embedded in the SMTP endpoint comment on
the cluster; increase it whenever the password is rotated so the Proxmox role
pushes the new credential on the next playbook run. The role refuses to enable
notifications while the file is missing, undecryptable, or still contains
`REPLACE_ME` placeholders.
