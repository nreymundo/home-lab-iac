output "firewall_ids" {
  description = "Firewall IDs keyed by stable firewall identifier"
  value       = module.firewall.firewall_ids
}

output "firewalls" {
  description = "Firewall metadata keyed by stable firewall identifier"
  value       = module.firewall.firewalls
}
