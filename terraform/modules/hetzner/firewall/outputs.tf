output "firewall_ids" {
  description = "Firewall IDs keyed by stable firewall identifier"
  value       = { for key, firewall in hcloud_firewall.this : key => firewall.id }
}

output "firewalls" {
  description = "Firewall metadata keyed by stable firewall identifier"
  value = {
    for key, firewall in hcloud_firewall.this : key => {
      id     = firewall.id
      name   = firewall.name
      labels = firewall.labels
    }
  }
}
