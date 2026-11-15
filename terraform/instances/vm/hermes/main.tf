module "unraid_vms" {
  source = "../../../modules/unraid/vm"

  vms = local.vm_definition
}
