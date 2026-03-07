# Jellyfin LDAP Configuration

This Jellyfin deployment authenticates against the Authentik LDAP outpost running in-cluster.

## Connection Settings

- LDAP server: `ak-outpost-ldap-outpost.authentik.svc.cluster.local`
- Port: `636`
- Secure LDAP: `true`
- Skip SSL/TLS verification: `true`
- Bind user: `cn=ldap-search,ou=users,dc=home,dc=lan`
- Bind password: value from the `ldap-search-secret` Kubernetes secret in the `authentik` namespace

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
