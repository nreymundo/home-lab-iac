# Troubleshooting Guide

Things break. Here's how to fix them.

## General Debugging Workflow

1.  **Is it DNS?** (It's usually DNS).
2.  **Is it Network?** (Can I ping it?).
3.  **Is the Pod running?** (`kubectl get pods`).
4.  **What do the logs say?** (`kubectl logs`).
5.  **Did Flux sync?** (`flux get kustomizations`).

## Component-Specific Issues

### 1. Provisioning (Terraform/Packer)

**Issue: Packer build hangs at boot.**
- **Cause:** Proxmox can't find the ISO or Cloud-init command is wrong.
- **Fix:** Open Proxmox console for the temporary VM. See what it's complaining about. Check `http/user-data` syntax.

**Issue: Terraform "Error: VM already exists".**
- **Cause:** You deleted the VM manually in Proxmox but Terraform state still thinks it exists.
- **Fix:** `terraform state rm proxmox_vm_qemu.k3s_node[0]` (adjust index).

### 2. Configuration (Ansible)

**Issue: "Unreachable" hosts.**
- **Cause:** SSH key mismatch or IP changed.
- **Fix:**
    - Check IP in `inventories/`.
    - `ssh ubuntu@<IP>` manually to accept host key / debug.
    - Check if VM is actually on.

### 3. Kubernetes (K3s)

**Issue: `kubectl` commands timeout.**
- **Cause:** API server is down or your IP changed.
- **Fix:**
    - Check `systemctl status k3s` on the master node.
    - Verify `~/.kube/config` points to the correct IP.

**Issue: Pods stuck in `ContainerCreating`.**
- **Cause:** Often storage (Longhorn) or network (CNI) issues.
- **Fix:** `kubectl describe pod <pod-name>`. Look at Events.

### 4. GitOps (Flux)

**Issue: Changes in Git aren't appearing.**
- **Cause:** Sync interval hasn't passed or reconciliation failed.
- **Fix:**
    ```bash
    flux reconcile source git flux-system
    flux reconcile kustomization flux-system
    ```
- **Debug:** `flux get all -A` to see what's broken.

**Issue: "Unknown CRD" errors.**
- **Cause:** Trying to create a resource (like `HelmRelease`) before the CRD is installed.
- **Fix:** Flux usually handles dependency order, but sometimes you need to manually wait or split the commit.

### 5. Storage (Longhorn)

**Issue: Volume stuck attaching/detaching.**
- **Cause:** Node failure or network blip left the volume locked.
- **Fix:** Longhorn UI -> Volumes -> Select Volume -> "Detach".

### 6. Networking (Traefik/Cert-Manager)

**Issue: Certificate issuance stuck.**
- **Cause:** Cloudflare token invalid or DNS propagation slow.
- **Fix:**
    - `kubectl describe order -A`
    - `kubectl describe challenge -A`

## Useful Commands Cheat Sheet

| Action | Command |
|--------|---------|
| **Get all pods** | `kubectl get pods -A` |
| **Why is pod broken?** | `kubectl describe pod <name> -n <ns>` |
| **Pod logs** | `kubectl logs <name> -n <ns>` |
| **Force Flux sync** | `flux reconcile kustomization flux-system --with-source` |
| **Check Nodes** | `kubectl get nodes -o wide` |
| **Check PVCs** | `kubectl get pvc -A` |
| **Restart Deployment** | `kubectl rollout restart deploy/<name> -n <ns>` |

## Where are the logs?

- **K3s Service:** `/var/log/syslog` (on nodes) or `journalctl -u k3s`
- **Traefik Access Logs:** By default stdout of Traefik pod.
- **Proxmox Logs:** Proxmox GUI -> Cluster -> Logs.
