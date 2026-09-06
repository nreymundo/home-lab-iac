# k3s role

Installs and configures the K3s cluster on the `k3s_cluster` inventory group.
A seed node (explicit `k3s_is_seed` host var, else the first `k3s_nodes` host)
boots with `--cluster-init`, then the remaining servers join through the API
VIP in `k3s_api_vip`.

What it manages:

- A pinned K3s release (`k3s_version` in `defaults/main.yml`) downloaded with
  SHA256 checksum verification, and its systemd unit.
- `/etc/rancher/k3s/registries.yaml` from the wildcard `k3s_registry_mirrors`,
  enabling the embedded registry for peer image sharing with direct-upstream
  fallback. Existing node-local `configs:` blocks are preserved across runs.
- Optional OS tuning, Raspberry Pi cgroup fixes, and workload taints per
  `k3s_allow_workloads`.
- The kubeconfig, fetched to `ansible/k3s.yaml` with the server address
  rewritten to the API VIP.

Operational entrypoints:

- [`../../playbooks/k3s_cluster.yml`](../../playbooks/k3s_cluster.yml) —
  install and reconcile the cluster.
- [`../../playbooks/k3s_upgrade.yml`](../../playbooks/k3s_upgrade.yml) —
  prechecks (node readiness, cgroups v2, deprecated flags), then a serial
  drain/upgrade/uncordon per node.

Validation follows [`../../AGENTS.md`](../../AGENTS.md): `ansible-lint` plus
`--syntax-check`, or `--check` with reachable hosts. Registry behavior and the
inter-node firewall requirements are covered in
[`../../../docs/kubernetes-bootstrap.md`](../../../docs/kubernetes-bootstrap.md)
and [`../../../SECURITY.md`](../../../SECURITY.md).
