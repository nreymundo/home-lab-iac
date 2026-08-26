module "proxmox_vms" {
  source = "../../../modules/proxmox/vm"

  vms = local.vm_definition
}
