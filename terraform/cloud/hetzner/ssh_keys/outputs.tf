output "ssh_key_ids" {
  description = "SSH key IDs keyed by stable SSH key identifier"
  value       = module.ssh_keys.ssh_key_ids
}

output "ssh_key_id_list" {
  description = "Flat list of Hetzner SSH key IDs for direct VM-module composition"
  value       = module.ssh_keys.ssh_key_id_list
}

output "ssh_keys" {
  description = "SSH key metadata keyed by stable SSH key identifier"
  value       = module.ssh_keys.ssh_keys
  sensitive   = true
}
