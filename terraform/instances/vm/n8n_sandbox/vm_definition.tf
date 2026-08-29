locals {
  vm_definition = [{
    name            = "vm-n8n-sandbox"
    target_node     = "pve3"
    vmid            = 253
    template_name   = "ubuntu-26.04-base"
    ci_user         = "sandbox"
    ansible_user    = "sandbox"
    ip_address      = "192.168.10.102"
    vm_cores        = 2
    vm_memory_mb    = 4096
    vm_balloon_mb   = 4096
    vm_disk_size_gb = 32
    proxmox_tags    = ["automation", "sandbox"]
  }]
}
