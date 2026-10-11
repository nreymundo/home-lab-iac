module "proxmox_vms" {
  source = "../../../modules/proxmox/vm"

  for_each = { for vm in local.vm_definitions : vm.name => vm }

  vms = [each.value]
}

moved {
  from = module.proxmox_vms.proxmox_vm_qemu.this[1]
  to   = module.proxmox_vms["k3s-node-02"].proxmox_vm_qemu.this[0]
}

moved {
  from = module.proxmox_vms.proxmox_vm_qemu.this[2]
  to   = module.proxmox_vms["k3s-node-03"].proxmox_vm_qemu.this[0]
}
