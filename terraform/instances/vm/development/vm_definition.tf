locals {
  vm_definition = [{
    name           = "development"
    ansible_user   = "dev"
    ip_address     = "192.168.10.101"
    vm_cores       = 8
    vm_memory_mb   = 12288
    disk_path      = "/mnt/apps/domains/development/vdisk1.qcow2"
    cloudinit_path = "/mnt/apps/domains/development/cloudinit.iso"
    os_type        = "ubuntu"
    running        = false
  }]
}
