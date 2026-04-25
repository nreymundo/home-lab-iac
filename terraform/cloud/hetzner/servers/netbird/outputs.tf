output "vms" {
  description = "VM metadata keyed by VM name for downstream consumers"
  value       = module.vm.vms
}
