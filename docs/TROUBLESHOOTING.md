# Troubleshooting Guide

Common issues and solutions for each component.

---

## Packer

### Build Fails to Start

**Symptom:** Packer hangs waiting for SSH or boot times out.

**Solutions:**
1. Verify ISO exists on Proxmox: `local:iso/<iso-name>`
2. Check boot command timing - increase delays if needed
3. Enable debug mode: `PACKER_LOG=1 ./build.sh`

### SSH Key Injection Fails

**Symptom:** Can't SSH to template after build.

**Solutions:**
1. Verify `BWS_ACCESS_TOKEN` is set
2. Check `http/user-data` was generated with keys:
   ```bash
   cat http/user-data | grep ssh-
   ```
3. Run `generate-autoinstall.sh` manually to debug

### Cloud-Init Not Running

**Symptom:** VM boots but isn't configured.

**Solutions:**
1. Check autoinstall syntax:
   ```bash
   cloud-init schema --config-file http/user-data
   ```
2. Verify HTTP server is accessible during build
3. Check VM console for cloud-init errors

---

## Terraform

### Authentication Errors

**Symptom:** `401 Unauthorized` or permission denied.

**Solutions:**
1. Verify environment variables:
   ```bash
   echo $PM_API_URL
   echo $PM_API_TOKEN_ID
   ```
2. Check API token has required permissions in Proxmox
3. Ensure API user exists and token isn't expired

### Template Not Found

**Symptom:** `Error: clone source template not found`

**Solutions:**
1. Verify template exists: `qm list | grep 9000`
2. Ensure template is on the target Proxmox node
3. Check `template_name` in `terraform.tfvars`

### State Lock Issues

**Symptom:** `Error acquiring state lock`

**Solutions:**
1. Check for other running Terraform processes
2. Force unlock (careful!):
   ```bash
   terraform force-unlock <lock-id>
   ```

### VM Creation Fails

**Symptom:** Terraform apply errors during VM creation.

**Solutions:**
1. Check Proxmox has enough resources (CPU, RAM, storage)
2. Verify network bridge exists: `ip link show vmbr0`
3. Check VMID isn't already in use

---

## Ansible

### SSH Connection Failures

**Symptom:** `UNREACHABLE!` or connection timeout.

**Solutions:**
1. Verify SSH key is in agent: `ssh-add -l`
2. Test manual SSH: `ssh ubuntu@<ip>`
3. Check inventory has correct IPs:
   ```bash
   ansible-inventory --list -i inventories/k3s-nodes.yml
   ```

### K3s Installation Fails

**Symptom:** K3s service won't start or nodes don't join.

**Solutions:**
1. Check K3s logs:
   ```bash
   journalctl -u k3s -f
   # or for agents:
   journalctl -u k3s-agent -f
   ```
2. Verify network interface (`k3s_iface`) is correct
3. Check firewall isn't blocking ports 6443, 10250

### Task Timeouts

**Symptom:** Long-running tasks timeout.

**Solutions:**
1. Increase async timeout in task
2. Check network connectivity to hosts
3. Verify package repositories are reachable

---

## Kubernetes / Flux

### HelmRelease Not Reconciling

**Symptom:** `HelmRelease stuck in progressing state.`

**Solutions:**
1. Check HelmRelease status:
   ```bash
   flux get helmrelease <name> -n <namespace>
   kubectl describe helmrelease <name> -n <namespace>
   ```
2. Check HelmRepository is ready:
   ```bash
   flux get sources helm -A
   ```
3. Force reconciliation:
   ```bash
   flux reconcile helmrelease <name> -n <namespace>
   ```

### Kustomization Failures

**Symptom:** Resources not being created.

**Solutions:**
1. Check Kustomization status:
   ```bash
   flux get kustomizations
   ```
2. View detailed errors:
   ```bash
   kubectl describe kustomization <name> -n flux-system
   ```
3. Validate manifests locally:
   ```bash
   kubectl apply --dry-run=client -f <path>
   ```

### Image Pull Errors

**Symptom:** `ErrImagePull` or `ImagePullBackOff`.

**Solutions:**
1. Check image exists and tag is correct
2. Verify registry credentials (if private)
3. Check pod events:
   ```bash
   kubectl describe pod <pod> -n <namespace>
   ```

### PVC Stuck in Pending

**Symptom:** `PersistentVolumeClaim is stuck in Pending.`

**Solutions:**
1. Check StorageClass exists:
   ```bash
   kubectl get storageclass
   ```
2. Verify Longhorn is healthy:
   ```bash
   kubectl get pods -n longhorn-system
   ```
3. Check Longhorn UI for volume provisioning status

### Ingress Not Working

**Symptom:** Service unreachable externally.

**Solutions:**
1. Check Ingress status:
   ```bash
   kubectl get ingress -A
   kubectl describe ingress <name> -n <namespace>
   ```
2. Verify Traefik is running:
   ```bash
   kubectl get pods -n traefik
   ```
3. Check Certificate status:
   ```bash
   kubectl get certificates -A
   ```
4. Test internal service:
   ```bash
   kubectl port-forward svc/<service> 8080:80 -n <namespace>
   ```

---

## General Debugging Commands

### Flux

```bash
# Overall status
flux get all -A

# View logs
flux logs --kind=HelmRelease --name=<name>

# Force sync from Git
flux reconcile source git flux-system
flux reconcile kustomization flux-system --with-source
```

### Kubernetes

```bash
# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Pod logs
kubectl logs <pod> -n <namespace> -f
kubectl logs <pod> -n <namespace> --previous  # crashed container

# Resource description
kubectl describe <resource> <name> -n <namespace>

# Get all resources in namespace
kubectl get all -n <namespace>
```

### Longhorn

```bash
# Check volumes
kubectl get volumes.longhorn.io -n longhorn-system

# Check replicas
kubectl get replicas.longhorn.io -n longhorn-system

# Access Longhorn UI (port-forward)
kubectl port-forward svc/longhorn-frontend 8080:80 -n longhorn-system
```

---

## Getting Help

1. Check component-specific `AGENTS.md` files for detailed instructions
2. Review Flux events and logs for GitOps issues
3. Check Proxmox task logs for VM/template issues
4. Enable verbose output (`-v` or `-vvv` for Ansible, `PACKER_LOG=1` for Packer)
