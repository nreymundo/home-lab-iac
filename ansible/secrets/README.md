# NetBird secrets

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
