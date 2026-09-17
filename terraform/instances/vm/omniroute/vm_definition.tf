locals {
  vm_definition = [{
    name            = "vm-omniroute"
    target_node     = "pve3"
    vmid            = 253
    template_name   = "ubuntu-26.04-base"
    ci_user         = "omniroute"
    ansible_user    = "omniroute"
    ip_address      = "192.168.10.102"
    vm_cores        = 4
    vm_memory_mb    = 16384
    vm_balloon_mb   = 16384
    vm_disk_size_gb = 64
    proxmox_tags    = ["ai"]
  }]
}
