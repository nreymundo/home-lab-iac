# Continuwuity

Continuwuity is deployed as a single-replica, non-federating Matrix homeserver
at `matrix.${CLUSTER_DOMAIN}`. This hostname is LAN-only through internal DNS
and the LAN allowlist middleware; the permanent Matrix identity is still
`matrix.${CLUSTER_DOMAIN}`, not a `.lan` name. Moving the service while
retaining this identity and complete state is an ordinary hosting move. The
server name cannot be changed in an existing database; changing it requires
fresh data/reset. State and database files share the `continuwuity` Longhorn
PVC.

Authentik native OIDC credentials are consumed from the replicated
`continuwuity-sso-secret` in namespace `comms`. Federation and open
registration are disabled. On a fresh database, the first successful OIDC
login becomes the admin; disabling registration does not block OIDC
just-in-time account creation. The intended human should log in first and
verify the admin-room invite before creating the local Hermes bot account and
issuing its token. User admission is governed by the Authentik
`ContinuwuityUsers` group. The Hermes bot must be a local account, not an OIDC
shadow account. Use the upstream [OIDC token guide](https://continuwuity.org/authentication/oidc#minting-tokens-for-non-oidc-accounts)
and [admin user reference](https://continuwuity.org/reference/admin/users.html)
for the exact commands.

Matrix clients should use end-to-end encryption (E2EE). Back up E2EE recovery
keys separately on Hermes; this repository does not implement Hermes crypto
backups. Server-side backups protect homeserver state but do not replace
clients' encrypted key/recovery material.

Longhorn recurring backups provide storage-level protection. Database files
on the PVC may be crash-consistent rather than application-consistent; for a
consistent offline copy, stop the workload and copy the PVC contents while it
is stopped. No separate database/PVC or automated stop-copy workflow is
managed here.
