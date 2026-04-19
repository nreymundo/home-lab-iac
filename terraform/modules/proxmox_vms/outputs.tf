output "vms" {
  description = "Normalized VM metadata for downstream inventory generation"
  value = [
    for idx, vm in local.normalized_vms : {
      name         = vm.name
      target_node  = vm.target_node
      vmid         = vm.vmid
      ip_address   = vm.ip_address
      ci_user      = vm.ci_user
      ansible_user = vm.ansible_user
      tags         = vm.proxmox_tags
      id           = proxmox_vm_qemu.this[idx].id
    }
  ]
}
