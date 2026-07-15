# NetBird secrets

`netbird.sops.yml` is committed encrypted. SOPS encrypts all `netbird_*` values
using the repository Age recipient:

```yaml
netbird_fqdn: netbird.example.com
netbird_acme_email: admin@example.com
netbird_owner_email: admin@example.com
netbird_owner_name: NetBird Owner
netbird_owner_password: replace-with-a-long-random-password
```

Edit and encrypt the file with:

```bash
sops ansible/secrets/netbird.sops.yml
```

The Ansible control host needs `sops` and access to the matching Age private key.
The role defaults to `~/.config/sops/age/keys.txt`; override it with
`SOPS_AGE_KEY_FILE` when the identity is stored elsewhere.
