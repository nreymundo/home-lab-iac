locals {
  vm_definition = {
    name           = "development"
    hostname       = "development"
    ansible_user   = "dev"
    ip_address     = "192.168.10.101"
    smbios_uuid    = "87dc43c0-7b18-4fd5-8505-ce37c6076b08"
    generation_id  = "61ab8c88-df92-43c5-bffa-3f949ff3ea97"
    cores          = 8
    memory_kib     = 12582912
    disk_directory = "/mnt/cache/domains/development"
  }
}
