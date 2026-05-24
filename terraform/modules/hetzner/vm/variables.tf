variable "vms" {
  type = list(object({
    name        = string
    server_type = string
    image       = string
    location    = string
    ssh_key_ids = optional(list(number), [])
    cloud_init = optional(object({
      username            = optional(string)
      ssh_authorized_keys = optional(list(string))
      ssh_port            = optional(number)
      extra_packages      = optional(list(string), [])
      ufw_rules = optional(list(object({
        port     = string
        protocol = optional(string, "tcp")
      })), [])
    }), null)
    firewall_ids       = optional(list(number), [])
    placement_group_id = optional(number, null)
    labels             = optional(map(string), {})
    backups            = optional(bool, false)
    user_data          = optional(string, null)
    delete_protection  = optional(bool, false)
    rebuild_protection = optional(bool, false)
    enable_public_ipv4 = optional(bool, true)
    enable_public_ipv6 = optional(bool, true)
    private_network = optional(object({
      network_id = number
      ip         = optional(string, null)
      alias_ips  = optional(list(string), [])
    }), null)
    volumes = optional(list(object({
      name      = string
      size      = number
      format    = optional(string, null)
      automount = optional(bool, false)
      labels    = optional(map(string), {})
    })), [])
  }))
  description = "Normalized VM definitions to provision in Hetzner Cloud"

  validation {
    condition     = length(distinct([for vm in var.vms : vm.name])) == length(var.vms)
    error_message = "Each VM name must be unique."
  }

  validation {
    condition     = alltrue([for vm in var.vms : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", vm.name))])
    error_message = "Each VM name must start with an alphanumeric character and contain only letters, numbers, underscores, dots, or hyphens."
  }

  validation {
    condition     = alltrue([for vm in var.vms : length(trimspace(vm.server_type)) > 0 && length(trimspace(vm.image)) > 0 && length(trimspace(vm.location)) > 0])
    error_message = "Each VM server_type, image, and location must be non-empty."
  }

  validation {
    condition = alltrue([
      for vm in var.vms : length(distinct([for volume in vm.volumes : volume.name])) == length(vm.volumes)
    ])
    error_message = "Volume names must be unique within each VM definition."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [
        for rule in coalesce(try(vm.cloud_init.ufw_rules, null), []) : contains(["tcp", "udp"], rule.protocol)
      ]
    ]))
    error_message = "Each cloud_init.ufw_rules protocol must be either 'tcp' or 'udp'."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [
        for label_key, label_value in vm.labels :
        can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", label_key)) && length(label_value) <= 63
      ]
    ]))
    error_message = "Each VM label key must be provider-safe and each label value must be 63 characters or fewer."
  }

  validation {
    condition = alltrue([
      for vm in var.vms :
      try(vm.cloud_init.username, null) == null || can(regex("^[A-Za-z_][A-Za-z0-9_.-]*[$]?$", vm.cloud_init.username))
    ])
    error_message = "Each cloud_init.username must be a valid local username."
  }

  validation {
    condition = alltrue([
      for vm in var.vms :
      try(vm.cloud_init.ssh_port, null) == null || (vm.cloud_init.ssh_port >= 1 && vm.cloud_init.ssh_port <= 65535)
    ])
    error_message = "Each cloud_init.ssh_port must be between 1 and 65535."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [
        for rule in coalesce(try(vm.cloud_init.ufw_rules, null), []) : length(trimspace(rule.port)) > 0 && trimspace(rule.port) != "any"
      ]
    ]))
    error_message = "Each cloud_init.ufw_rules port must be a non-empty explicit port value, not 'any'."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [
        for rule in coalesce(try(vm.cloud_init.ufw_rules, null), []) : can(regex("^[0-9]+(:[0-9]+)?$", rule.port))
      ]
    ]))
    error_message = "Each cloud_init.ufw_rules port must be a numeric port or port range."
  }
}

variable "default_labels" {
  type        = map(string)
  description = "Module-level labels merged into each VM label map"
  default     = {}

  validation {
    condition = alltrue([
      for label_key, label_value in var.default_labels :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", label_key)) && length(label_value) <= 63
    ])
    error_message = "Each default label key must be provider-safe and each label value must be 63 characters or fewer."
  }
}

variable "default_cloud_init" {
  type = object({
    username            = string
    ssh_authorized_keys = list(string)
    ssh_port            = optional(number, 22)
    extra_packages      = optional(list(string), [])
    ufw_rules = optional(list(object({
      port     = string
      protocol = optional(string, "tcp")
    })), [])
  })
  description = "Default generated cloud-init settings applied to VMs unless overridden per VM"
  default     = null

  validation {
    condition = var.default_cloud_init == null ? true : alltrue([
      for rule in var.default_cloud_init.ufw_rules : contains(["tcp", "udp"], rule.protocol)
    ])
    error_message = "Each default_cloud_init.ufw_rules protocol must be either 'tcp' or 'udp'."
  }

  validation {
    condition     = var.default_cloud_init == null ? true : can(regex("^[A-Za-z_][A-Za-z0-9_.-]*[$]?$", var.default_cloud_init.username))
    error_message = "default_cloud_init.username must be a valid local username."
  }

  validation {
    condition     = var.default_cloud_init == null ? true : var.default_cloud_init.ssh_port >= 1 && var.default_cloud_init.ssh_port <= 65535
    error_message = "default_cloud_init.ssh_port must be between 1 and 65535."
  }

  validation {
    condition = var.default_cloud_init == null ? true : alltrue([
      for rule in var.default_cloud_init.ufw_rules : length(trimspace(rule.port)) > 0 && trimspace(rule.port) != "any"
    ])
    error_message = "Each default_cloud_init.ufw_rules port must be a non-empty explicit port value, not 'any'."
  }

  validation {
    condition = var.default_cloud_init == null ? true : alltrue([
      for rule in var.default_cloud_init.ufw_rules : can(regex("^[0-9]+(:[0-9]+)?$", rule.port))
    ])
    error_message = "Each default_cloud_init.ufw_rules port must be a numeric port or port range."
  }
}
