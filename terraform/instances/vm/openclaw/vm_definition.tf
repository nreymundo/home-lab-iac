locals {
  vm_definition = [{
    name            = "vm-openclaw"
    target_node     = "pve2"
    vmid            = 104
    ci_user         = "openclaw"
    ansible_user    = "openclaw"
    ip_address      = "192.168.10.12"
    vm_cores        = 4
    vm_memory_mb    = 6144
    vm_balloon_mb   = 6144
    vm_disk_size_gb = 64
    proxmox_tags    = []
  }]
}
