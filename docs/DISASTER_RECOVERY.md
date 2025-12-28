# Disaster Recovery

Hope for the best, plan for the "rm -rf /".

## What IS Backed Up?
- **Infrastructure Code:** GitHub (This repo). This is the source of truth.
- **Secrets:** Bitwarden.
- **Persistent Data:** (Planned) Longhorn backups to S3/NFS.
- **Databases:** (Planned) CloudNative-PG backups to S3/NFS.

## What IS NOT Backed Up?
- **VM Root Disks:** They are ephemeral. I can rebuild them with Terraform/Ansible.
- **Logs:** If Loki dies, logs are gone. I accept this.
- **Test Data:** Anything in a pod without a PVC.

## Recovery Scenarios

### Scenario 1: I deleted a Deployment by mistake
**Fix:**
1.  Do nothing.
2.  Wait 10 minutes.
3.  Flux will realize the cluster state doesn't match Git and recreate it.
4.  *Faster fix:* `flux reconcile kustomization flux-system`.

### Scenario 2: A K3s Node died (VM corruption)
**Fix:**
1.  **Proxmox:** Delete the corrupted VM.
2.  **Terraform:** `terraform apply`. It will detect the missing VM and recreate it.
3.  **Ansible:** Run the playbooks to configure the new VM and install K3s.
4.  **Cluster:** The new node joins. Longhorn rebuilds data replicas onto the new node.

### Scenario 3: Proxmox Host Died (Hardware Failure)
**Fix:**
1.  Cry.
2.  Replace hardware.
3.  Install Proxmox VE.
4.  Restore VM backups (if using Proxmox Backup Server) OR just run Terraform/Ansible to rebuild.
5.  *Data on Longhorn might be lost if all replicas were on that one host (which shouldn't happen with anti-affinity).*

### Scenario 4: Total Cluster Meltdown (The "Nuke It" Option)
If the cluster is unrecoverable (etcd corruption, bad upgrade, chaos):

1.  **Terraform:** `terraform destroy`.
2.  **Terraform:** `terraform apply`.
3.  **Ansible:** Run all playbooks.
4.  **Flux:** Bootstrap the new cluster.
    ```bash
    flux bootstrap github ...
    ```
5.  **Secrets:** Re-apply the bootstrap secrets (Bitwarden token).
6.  **Wait:** Flux installs everything.
7.  **Restore Data:** (If backups exist) Restore Longhorn backups to the new PVCs.

## Backup Strategy (Planned)

### Longhorn
- **Target:** S3 (AWS or MinIO on RPi).
- **Schedule:** Daily.
- **Retention:** 7 days.

### Etcd (K3s)
- K3s does this automatically to `/var/lib/rancher/k3s/server/db/snapshots`.
- **Action:** Need to sync these snapshots off-node (e.g., via Ansible fetch or cron/rsync).
