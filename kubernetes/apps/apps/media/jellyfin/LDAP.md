# Jellyfin LDAP Configuration

Jellyfin runs on Unraid and authenticates against the in-cluster Authentik LDAP outpost via its LAN endpoint.

These settings are managed by the `jellyfin-automation` CronJob (`17 */6 * * *`)
using [automation-config.yaml](automation-config.yaml). Both are included by the
[Jellyfin app root](kustomization.yaml) under `apps-manifests`. The job installs
the LDAP plugin if missing; Jellyfin must load it after restart before the job
can configure it. The job preserves existing LDAP account links and validates
the bind and search filters. Change managed settings in Git, not only in the UI.

## Connection Settings

- LDAP server: `ldap.lan.${CLUSTER_DOMAIN}`
- Port: `636`
- Secure LDAP: `true`
- Skip SSL/TLS verification: `true`
- Bind user: `cn=ldap-search,ou=users,dc=home,dc=lan`
- Bind password: `AK_LDAP_SEARCH_PASSWORD` from `ldap-search-secret`, owned
  by Authentik and replicated by kube-replicator into `media`. The CronJob
  reads the replica at `/ldap-credentials/AK_LDAP_SEARCH_PASSWORD`.

## Search Settings

- LDAP base DN: `ou=users,dc=home,dc=lan`
- LDAP search filter: `(&(objectClass=user)(|(memberOf=cn=Jellyfin Users,ou=groups,dc=home,dc=lan)(memberOf=cn=Jellyfin Admins,ou=groups,dc=home,dc=lan)))`
- LDAP search attributes: `uid, cn, mail, displayName`
- LDAP UID attribute: `uid`
- LDAP username attribute: `cn`
- LDAP password attribute: `userPassword`

## Admin Mapping

- LDAP admin base DN: `ou=users,dc=home,dc=lan`
- LDAP admin filter: `(memberOf=cn=Jellyfin Admins,ou=groups,dc=home,dc=lan)`

## Optional Fields

- Enable profile image sync: `false`
- LDAP profile image attribute: leave blank

## Group Model

- `Jellyfin Users`: users allowed to sign in
- `Jellyfin Admins`: users allowed to sign in and receive Jellyfin admin access

## Notes

- Do not include `{0}` in the custom Jellyfin LDAP search or admin filters. The Jellyfin plugin appends its own username match clause.
- The LDAP outpost exposes both `389` and `636`, but Jellyfin is currently configured to use LDAPS on `636` with certificate verification disabled.
