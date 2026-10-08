# k3s role

Selected-server provisioning for Ubuntu 24.04/26.04, using embedded etcd on
VMs or bare metal. General host setup runs first through `ubuntu.yml`.

## Entry points

- `k3s_cluster.yml`: join a new server or reconcile an existing server.
- `k3s_bootstrap.yml`: explicitly initialize a fresh cluster, then join the
  remaining selected servers. Existing datastore state is rejected.
- `k3s_upgrade.yml`: upgrade selected servers, one at a time.

Both reconciliation and upgrades use `serial: 1`, `any_errors_fatal: true`,
health gates and the same drain/restart/recovery sequence. A no-op run does not
drain or restart. Failed maintenance leaves its node cordoned and stops later
targets. A pre-existing cordon is retained after success.

## Inputs

| Variable | Contract |
| --- | --- |
| `k3s_admin_host` | Required existing inventory server for token/admin operations, even when outside `--limit`. Fleet value: `k3s-node-02`. |
| `k3s_bootstrap_host` | First server for the explicit fresh-bootstrap playbook. Must be selected. |
| `k3s_version`, architecture checksums | Pinned install/upgrade release. Reconciliation rejects an existing server at a different release. New joins must match the administrative server. |
| `k3s_api_vip` | Existing API address and TLS SAN, `192.168.10.10`. |
| `k3s_join_url`, `k3s_admin_api_url` | Default to `https://<VIP>:6443`; disposable clusters can supply a reachable server endpoint. |
| `k3s_node_ip`, `k3s_iface` | Inventory IP and selected network interface. |
| `k3s_storage_mode` | `manual` by default; existing `k3s_nodes` explicitly select `managed`. |
| `k3s_storage_expected_uuid`, `k3s_storage_expected_source` | Optional checks against the mounted Longhorn filesystem. |
| `k3s_disable_multipathd` | `true`: stop/disable/mask an installed multipathd service on dedicated Longhorn hosts. |
| `k3s_node_labels` | Apply declared label values only to the selected node; other labels remain intact. |
| `k3s_allow_workloads` | Own the `workloads:NoSchedule` taint for the selected node. |
| `k3s_fetch_kubeconfig` | Default `false`; explicitly write a controller kubeconfig at mode `0600` when requested. |
| `k3s_drain_force`, `k3s_drain_disable_eviction` | Default `false`; drain normally respects eviction/PDB behaviour. |

Existing service rendering retains the original role's arguments and whitespace.
It adds no new network/DNS flags, mount dependency or nofile drop-in to current
members. The application's `CLUSTER_DOMAIN` is not used for Kubernetes DNS.

## Host/storage ownership

New-node preparation owns Kubernetes modules/sysctls, swap disabling, iSCSI and
Longhorn dependencies. `swapfile_enabled` must be false, including host-level overrides.
It comments active fstab swap entries and disables active swap without removing
the underlying swap files or partitions. Explicitly enabled swap units and other
swap providers must be disabled before enrollment.

Existing members receive read-only host/storage inspection. Their packages,
swap, modules, sysctls, tuning files and disk preparation are not reprovisioned.
Observed existing swap is reported, not disabled as an enrollment side effect.

Manual storage requires a read/write ext4/XFS filesystem mounted at exactly
`/var/lib/longhorn`, with a matching evaluated fstab entry. XFS requires `ftype=1`.
The role performs a temporary write/fsync probe for new nodes outside check mode. It never
partitions or formats in manual mode. Managed storage reuses `secondary_disk`;
unexpected disk signatures, partitions and filesystem types are rejected.

Existing nofile units/drop-ins are retained without adopting new files. Host
tuning changes belong to a deliberate host-maintenance operation.

## Credentials and cluster identity

The existing server token is read through delegated `slurp`. New joining servers
receive `/etc/rancher/k3s/server-token` at mode `0600`, referenced by filename.
Already installed servers retain their original inline-token or token-file layout;
ordinary reconciliation does not convert credentials or introduce a token file.
Token/registry
tasks suppress logs and diffs; no token file is saved on the controller.
The initial server retains `--cluster-init` independently of administrative
host selection; existing embedded-etcd state remains authoritative.

Existing node-local registry `configs:` (including manual Docker Hub auth) is
preserved. Malformed registry YAML fails instead of silently discarding it.
Embedded peer sharing and direct upstream fallback remain enabled.

Before reconciliation, local and administrative cluster identities must agree.
Node registration must match local datastore presence. After recovery, the
cluster UID is rechecked. No workflow resets or removes datastore contents.

Upgrades change only the requested binary version and service runtime state.
They do not rewrite service/registry/tuning files, token layout or node metadata,
even if unrelated configuration variables differ during the upgrade invocation.

## Validation

See [the provisioning runbook](../../../docs/k3s-provisioning.md) for commands,
scope of check mode, disposable-cluster acceptance and migration order.
