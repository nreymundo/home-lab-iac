locals {
  vm_definition = [{
    name           = "development"
    ansible_user   = "dev"
    ip_address     = "192.168.10.101"
    vm_cores       = 8
    vm_memory_mb   = 12288
    disk_path      = "/mnt/cache/domains/development/vdisk1.qcow2"
    cloudinit_path = "/mnt/cache/domains/development/cloudinit.iso"
    mac_address    = "bc:24:11:16:c2:fc"
    smbios_uuid    = "87dc43c0-7b18-4fd5-8505-ce37c6076b08"
    generation_id  = "61ab8c88-df92-43c5-bffa-3f949ff3ea97"
    os_type        = "ubuntu"
  }]
}
