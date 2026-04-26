output "vms" {
  description = "VM metadata keyed by VM name for downstream consumers"
  value       = local.ansible_inventory_vms
}
