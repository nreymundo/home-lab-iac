locals {
  vm_definition = [{
    name            = "vm-hermes"
    target_node     = "pve2"
    vmid            = 250
    template_name   = "ubuntu-26.04-base"
    ci_user         = "hermes"
    ansible_user    = "hermes"
    ip_address      = "192.168.10.100"
    vm_cores        = 4
    vm_memory_mb    = 12288
    vm_balloon_mb   = 8192
    vm_disk_size_gb = 128
    proxmox_tags    = ["ai"]
  }]
}
