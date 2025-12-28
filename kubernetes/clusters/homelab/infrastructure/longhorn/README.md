# Longhorn Storage

Longhorn provides distributed block storage for the cluster. It turns the secondary disks of our VMs into a resilient storage pool.

## Architecture

```mermaid
graph TD
    Pod[Pod] --> PVC[PVC]
    PVC --> PV[PV]
    PV --> LH[Longhorn Volume]
    LH --> Replica1[Replica on Node 1]
    LH --> Replica2[Replica on Node 2]

    Replica1 --> Disk1[/dev/sdb Node 1]
    Replica2 --> Disk2[/dev/sdb Node 2]
```

- **Replicas:** 2 (Configured in StorageClass).
- **Disk:** Uses the `/var/lib/longhorn` mount point (mapped to `/dev/sdb`).
- **Backup Target:** (Planned) S3.

## StorageClasses

### `longhorn` (Default)
- **Replication:** 2 copies.
- **Expansion:** Online expansion supported.
- **Access Modes:** ReadWriteOnce (RWO).

## Usage

To use Longhorn, just request storage in your PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

## Operations

### Accessing the UI
The dashboard is available at: `longhorn.lan.<DOMAIN>`

### Increasing Volume Size
1.  Edit the PVC yaml.
2.  Change `10Gi` to `20Gi`.
3.  Apply.
4.  Longhorn automatically expands the volume and the filesystem (no downtime).

### Backups
(To be configured)
- Snapshot: Instant, local.
- Backup: Off-site to S3.

## Troubleshooting

### Volume Detached / Attach Failed
If a node crashes hard, a volume might get stuck "Attached" to the dead node.
**Fix:** Go to Longhorn UI -> Volumes -> Select Volume -> "Detach".

### Disk Pressure
If `/var/lib/longhorn` fills up:
1.  Check which volume is hogging space.
2.  Expand the underlying VM disk (Terraform + Ansible).
3.  Resize the LVM/Ext4 filesystem on the node.
