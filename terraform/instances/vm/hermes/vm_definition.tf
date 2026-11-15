locals {
  vm_definition = [{
    name               = "hermes"
    hostname           = "hermes"
    ansible_user       = "hermes"
    ip_address         = "192.168.10.100"
    vm_cores           = 4
    vm_memory_mb       = 12288
    disk_path          = "/mnt/apps/domains/hermes/vdisk1.qcow2"
    cloudinit_path     = "/mnt/apps/domains/hermes/cloudinit.iso"
    os_type            = "ubuntu"
    start_at_node_boot = true
  }]
}
