locals {
  openclaw = {
    vm_name         = "vm-openclaw"
    target_node     = "pve1"
    vmid            = 104
    ip_address      = "192.168.10.12"
    ci_user         = "openclaw"
    ansible_user    = null
    vm_cores        = 4
    vm_memory_mb    = 4096
    vm_balloon_mb   = 4096
    vm_disk_size_gb = 64
    proxmox_tags    = []
  }

  vm_definition = [{
    name            = local.openclaw.vm_name
    target_node     = local.openclaw.target_node
    vmid            = local.openclaw.vmid
    ci_user         = local.openclaw.ci_user
    ansible_user    = coalesce(local.openclaw.ansible_user, local.openclaw.ci_user)
    ip_address      = local.openclaw.ip_address
    vm_cores        = local.openclaw.vm_cores
    vm_memory_mb    = local.openclaw.vm_memory_mb
    vm_balloon_mb   = local.openclaw.vm_balloon_mb
    vm_disk_size_gb = local.openclaw.vm_disk_size_gb
    proxmox_tags    = local.openclaw.proxmox_tags
  }]
}
