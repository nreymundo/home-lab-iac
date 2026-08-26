locals {
  vm_definition = [{
    name            = "vm-dev"
    target_node     = "pve3"
    vmid            = 252
    template_name   = "ubuntu-26.04-base"
    ci_user         = "dev"
    ansible_user    = "dev"
    ip_address      = "192.168.10.101"
    vm_cores        = 8
    vm_memory_mb    = 16384
    vm_balloon_mb   = 12288
    vm_disk_size_gb = 256
    proxmox_tags    = ["development"]
  }]
}
