locals {
  firewalls_by_key = {
    for key, firewall in var.firewalls : key => {
      name   = coalesce(try(firewall.name, null), key)
      labels = merge(var.default_labels, coalesce(try(firewall.labels, null), {}))
      rules  = firewall.rules
    }
  }
}

resource "hcloud_firewall" "this" {
  for_each = local.firewalls_by_key

  name   = each.value.name
  labels = each.value.labels

  dynamic "rule" {
    for_each = each.value.rules
    content {
      direction       = rule.value.direction
      protocol        = rule.value.protocol
      port            = try(rule.value.port, null)
      source_ips      = try(rule.value.source_ips, null)
      destination_ips = try(rule.value.destination_ips, null)
      description     = try(rule.value.description, null)
    }
  }
}
