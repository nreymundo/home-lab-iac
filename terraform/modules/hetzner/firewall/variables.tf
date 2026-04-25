variable "firewalls" {
  type = map(object({
    name   = optional(string)
    labels = optional(map(string), {})
    rules = list(object({
      direction       = string
      protocol        = string
      port            = optional(string)
      source_ips      = optional(list(string))
      destination_ips = optional(list(string))
      description     = optional(string)
    }))
  }))
  description = "Hetzner firewalls to create, keyed by a stable identifier"

  validation {
    condition     = alltrue([for firewall in values(var.firewalls) : length(firewall.rules) > 0])
    error_message = "Each firewall must define at least one rule."
  }

  validation {
    condition = alltrue(flatten([
      for firewall in values(var.firewalls) : [
        for rule in firewall.rules : contains(["in", "out"], rule.direction)
      ]
    ]))
    error_message = "Each firewall rule direction must be either 'in' or 'out'."
  }

  validation {
    condition = alltrue(flatten([
      for firewall in values(var.firewalls) : [
        for rule in firewall.rules : contains(["tcp", "udp", "icmp", "gre", "esp"], rule.protocol)
      ]
    ]))
    error_message = "Each firewall rule protocol must be one of tcp, udp, icmp, gre, or esp."
  }

  validation {
    condition = alltrue(flatten([
      for firewall in values(var.firewalls) : [
        for rule in firewall.rules : contains(["tcp", "udp"], rule.protocol) ? try(rule.port, null) != null : true
      ]
    ]))
    error_message = "Each tcp/udp firewall rule must define a port."
  }

  validation {
    condition = alltrue(flatten([
      for firewall in values(var.firewalls) : [
        for rule in firewall.rules : rule.direction == "in" ? length(coalesce(try(rule.source_ips, null), [])) > 0 : true
      ]
    ]))
    error_message = "Each inbound firewall rule must define at least one source_ips CIDR."
  }

  validation {
    condition = alltrue(flatten([
      for firewall in values(var.firewalls) : [
        for rule in firewall.rules : rule.direction == "out" ? length(coalesce(try(rule.destination_ips, null), [])) > 0 : true
      ]
    ]))
    error_message = "Each outbound firewall rule must define at least one destination_ips CIDR."
  }
}

variable "default_labels" {
  type        = map(string)
  description = "Module-level labels merged into each firewall label map"
  default     = {}
}
