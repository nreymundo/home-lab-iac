# K3s server provisioning

The K3s role manages Ubuntu 24.04/26.04 embedded-etcd servers. Run commands from
`ansible/`; see the [Ubuntu guide](ubuntu-host-provisioning.md) for host setup.

## Join a server

1. Add bare metal to hand-maintained `k3s_baremetal`. It is nested under
   `ubuntu_baremetal`; VM identities are Terraform-generated and must not be edited.
2. Set host IP and `k3s_iface`. Set `swapfile_enabled: false`; the Ubuntu swap
   role does not remove active swap.
3. Prepare an ext4/XFS filesystem mounted persistently at `/var/lib/longhorn`.
   Set `k3s_storage_mode: manual`; optionally set its expected UUID/source. The
   role validates this mount but does not format disks or edit fstab. The K3s
   service requires it at startup. Managed VMs use `secondary_disk_*` settings.
4. Ensure the host reaches the API VIP (`192.168.10.10`) and admin server. The
   default admin is `k3s-node-02`; admin/join URLs use the VIP. Match
   `k3s_version` to the running cluster and allow required traffic per
   [SECURITY.md](../SECURITY.md).
5. Provision the host, then check and join only that server:

   ```sh
   ansible-playbook playbooks/ubuntu.yml --limit <host>
   ansible-playbook playbooks/k3s_cluster.yml --limit <host> --check
   ansible-playbook playbooks/k3s_cluster.yml --limit <host>
   ```

Only the limited host is changed. Admin queries and token retrieval use
`k3s_admin_host`, even outside `--limit`; an unavailable admin never triggers
bootstrap. Node names must match inventory hostnames. Configure Docker Hub
credentials separately; see the
[Kubernetes bootstrap guide](kubernetes-bootstrap.md).

## Reconcile and upgrade

Reconcile one or more servers with:

```sh
ansible-playbook playbooks/k3s_cluster.yml --limit <hosts>
```

An unchanged run does not drain or restart. Changes run one server at a time.
Drains honor eviction/PDBs, ignore DaemonSets and allow emptyDir deletion. Force
and disabling eviction are opt-in. Failure stops later servers and leaves a
drained server cordoned for explicit recovery; existing cordons remain after success.

The role checks local/admin cluster identity before changing an existing server.
Partial/SQLite installations and registration/datastore mismatches fail; the role
does not reset or recover datastore contents. Upgrades are serial too:

```sh
ansible-playbook playbooks/k3s_upgrade.yml --limit <hosts> --check
ansible-playbook playbooks/k3s_upgrade.yml --limit <hosts>
```

Update version and architecture checksums together. Upgrades reject downgrades
and skipped minor releases; finish one minor release across the fleet before the
next. Upgrades change the binary, not service, registry or node metadata config.

## Fresh bootstrap

Bootstrap only a new cluster with no datastore. Prepare three servers and
storage, then set `k3s_bootstrap_host` to the first selected server:

```sh
ansible-playbook playbooks/k3s_bootstrap.yml --limit <first>,<second>,<third>
```

If bootstrap stops after initialization, resume with
`k3s_cluster.yml --limit <remaining-servers>` and use the initialized server as
`k3s_admin_host`. Never bootstrap an existing datastore.

## Check mode and replacement

K3s check mode connects and reads cluster state, health and credentials. It does
not join, restart, drain, change metadata, fetch kubeconfig or run the storage
write probe. It cannot prove a join will succeed; an unprepared managed disk can
fail check-mode validation.

Before replacement, verify cluster and Longhorn replica health. Maintain three
healthy voters; a temporary fourth tolerates only one failure. Promote and
verify the replacement before retiring the old server. Update API backends and
protect Longhorn replicas and application data.

Check playbook syntax from `ansible/` with:

```sh
ansible-playbook playbooks/k3s_cluster.yml --syntax-check
```

See the [offline test guide](../ansible/tests/README.md); fixtures do not prove
live etcd, networking, storage persistence or service recovery.
