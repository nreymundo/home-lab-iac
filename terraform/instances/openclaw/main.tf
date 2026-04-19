module "proxmox_vms" {
  source = "../../modules/proxmox_vms"

  vms = local.vm_definition
}
