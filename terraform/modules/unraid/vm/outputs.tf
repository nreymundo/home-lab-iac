output "vms" {
  description = "VM metadata for downstream inventory generation."
  value = [
    for vm in var.vms : {
      name         = vm.name
      hostname     = coalesce(vm.hostname, vm.name)
      ip_address   = vm.ip_address
      ansible_user = vm.ansible_user
      uuid         = libvirt_domain.this[vm.name].uuid
    }
  ]
}
