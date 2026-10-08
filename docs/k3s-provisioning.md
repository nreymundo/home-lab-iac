# Incremental K3s server provisioning

Run commands from `ansible/` so `ansible.cfg` supplies inventory and role paths.
The supported server hosts are Ubuntu 24.04 and 26.04 with embedded etcd.

## Prepare and join one host

1. Install Ubuntu and configure SSH access.
2. Add the host to hand-maintained inventory under `k3s_baremetal`. This also
   includes it in `ubuntu_hosts` through `ubuntu_baremetal`. VM identities stay
   in Terraform-generated `k3s_nodes`; do not hand-edit generated inventory.
3. Set host IP/interface, intended labels and `swapfile_enabled: false`.
   Existing laptop host overrides take precedence over group defaults: change
   that override when enrolling the laptop. Its inventory membership is not
   changed automatically by this implementation.
4. Provision the host:

   ```sh
   ansible-playbook playbooks/ubuntu.yml --limit <new-server>
   ```

5. Prepare and persist an ext4/XFS mount at `/var/lib/longhorn` in `/etc/fstab`.
   Optionally record its expected UUID/source in host variables. Bare-metal
   storage uses `k3s_storage_mode: manual`. Existing VMs explicitly use
   `managed` with the existing `secondary_disk_*` inputs.
6. Ensure `k3s_admin_host` identifies a healthy, SSH-reachable existing server
   (`k3s-node-02` initially). The existing API VIP must be reachable from both
   the new server and administrative server. Configure required node firewall
   connectivity as described in [SECURITY.md](../SECURITY.md).
7. Confirm the pinned `k3s_version` equals the cluster's running release, then:

   ```sh
   ansible-playbook playbooks/k3s_cluster.yml --limit <new-server> --check
   ansible-playbook playbooks/k3s_cluster.yml --limit <new-server>
   ```

`--limit` selects which servers are changed. Administrative queries and token
retrieval delegate to the explicit administrative server even outside that
limit. No roles are provisioned on the administrative server merely because
it is used for delegation. A missing/unavailable administrator never triggers
bootstrap. Registered node names must equal their inventory hostnames.

The role checks API/datastore readiness and registered-node readiness, joins
the server, checks the original cluster UID, and applies that node's declared
labels/workload taint. Existing registry authentication is preserved. Configure
Docker Hub auth manually on a new node as described in the
[Kubernetes bootstrap runbook](kubernetes-bootstrap.md).

## Reconcile configuration

```sh
ansible-playbook playbooks/k3s_cluster.yml --limit <selected-server>
```

An unchanged run does not drain or restart, including the first run over members
provisioned by the original role. Their service rendering, token layout, registry
contents and tuning files are retained. Enrollment preparation is limited to new
nodes; existing host/storage state is inspected without reprovisioning it.
An intentional service/registry configuration change drains and restarts one
existing server at a time.

The role retains the original embedded-etcd datastore. It compares the local
cluster UID with the administrative cluster before changing an existing node.
It rejects partial/SQLite installations and registration/datastore mismatches;
resolve those explicitly rather than expecting automatic recovery/reset.

Existing network flags and defaults retain the original rendering contract.
New servers must use cluster-compatible settings; joining does not introduce
network/DNS flags on existing servers. Application `CLUSTER_DOMAIN` is not mapped
to Kubernetes DNS.

## Upgrade selected servers

Update `k3s_version` and architecture checksums together, then:

```sh
ansible-playbook playbooks/k3s_upgrade.yml --limit <selected-servers> --check
ansible-playbook playbooks/k3s_upgrade.yml --limit <selected-servers>
```

Targets follow inventory order with `serial: 1`; the administrative endpoint uses
the VIP even when its own K3s service is restarted. Existing servers at another
release are rejected by the ordinary reconciliation playbook. The upgrade
entrypoint rejects downgrades and skipped minor releases. Complete an upgrade
across the server fleet before beginning the next minor release; the cluster-wide
server version gate also checks servers outside `--limit`.

An upgrade changes the binary and performs its rolling restart; it does not also
reconcile service files, registry settings, token layout, tuning or node metadata.

Drains use eviction, preserve PDB behaviour, ignore DaemonSets, and permit
emptyDir deletion. Force/disable-eviction remain explicit, default-off inputs.
Failure stops later targets and leaves a drained node cordoned. A node already
cordoned before this invocation remains cordoned after success; if a previous
failed invocation cordoned it, inspect recovery and uncordon it explicitly.

## Explicit fresh bootstrap

Use only for a fresh cluster, not for replacement servers:

```sh
ansible-playbook playbooks/k3s_bootstrap.yml --limit <first>,<second>,<third>
```

Set `k3s_bootstrap_host` to the first selected server and prepare all three hosts
and storage beforehand. This host must have no existing datastore. Subsequent
servers join sequentially using its token. The initial server checks its own API
locally; joins still require a reachable registration endpoint. For disposable
clusters without the production VIP, override `k3s_api_vip`, `k3s_join_url` and
`k3s_admin_api_url` with that cluster's addresses.

If bootstrap is interrupted after initialization, resume joining with
`k3s_cluster.yml --limit <remaining-servers>` and point `k3s_admin_host` to the
initialized server. Do not rerun fresh bootstrap against an existing datastore.

## Check mode and evidence

Check mode reads real inventory, local state and existing-cluster health/token
information but does not join, restart, drain, alter node metadata, fetch a
kubeconfig or perform the storage write probe. It cannot prove readiness of
future services. An unprepared managed disk may fail storage validation in
check mode because the predicted partition/mount does not exist yet.

Offline tests execute the real Ansible orchestration with redirected temporary
files and simulated K3s/download/systemd boundaries. Frozen original-role fixtures
cover both initial and joining servers: the first run of the new role must leave
their files unchanged, create no token/drop-in, and perform no drain or restart.
The tests also cover delegation
outside `--limit`, bootstrap, no-op reruns, metadata/credential preservation,
upgrades, failure stops and cordon state. They do not establish actual etcd,
Longhorn, networking, OS prerequisite persistence or service recovery behaviour.

Before production membership changes, use disposable Ubuntu 24.04/26.04 VMs:

1. Provision host prerequisites and storage; reboot and verify persistence.
2. Bootstrap three servers and record the `kube-system` namespace UID.
3. Join a fourth with `--limit` selecting only it; confirm unchanged UID and
   healthy four-member etcd membership.
4. Rerun unchanged; verify no drain and unchanged service start timestamps.
5. Change selected-node configuration and verify one-at-a-time recovery.
6. Upgrade selected servers; inspect versions, datastore and workloads.
7. Exercise a blocked drain, failed restart and pre-existing cordon; verify no
   later target is changed, then recover the fixture.
8. Confirm Longhorn disk/replica health before treating it as migration-ready.

## Production replacement sequence

Maintain three servers, temporarily four while replacing one. Verify cluster
and Longhorn replica health before retiring the old server and returning to
three. Four voters still tolerate only one failed voter.

Update API load-balancer backends explicitly as membership changes. Before
retiring the administrative server, select another existing administrator in
inventory. Handle hostname-pinned workloads/GPU resources and VM retirement as
separate migration steps. Reinstalling `pve3` also requires relocation of its
other guests and host data, including backup/backend services.
