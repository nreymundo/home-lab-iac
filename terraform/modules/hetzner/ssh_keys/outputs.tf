output "ssh_key_ids" {
  description = "SSH key IDs keyed by stable SSH key identifier"
  value       = { for key, ssh_key in hcloud_ssh_key.this : key => ssh_key.id }
}

output "ssh_key_id_list" {
  description = "Flat list of Hetzner SSH key IDs for direct VM-module composition"
  value       = [for key, ssh_key in hcloud_ssh_key.this : ssh_key.id]
}

output "ssh_keys" {
  description = "SSH key metadata keyed by stable SSH key identifier"
  value = {
    for key, ssh_key in hcloud_ssh_key.this : key => {
      id          = ssh_key.id
      name        = ssh_key.name
      fingerprint = ssh_key.fingerprint
      labels      = ssh_key.labels
    }
  }
}
