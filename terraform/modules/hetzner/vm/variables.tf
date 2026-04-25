variable "vms" {
  type = list(object({
    name               = string
    server_type        = string
    image              = string
    location           = string
    ssh_key_ids        = optional(list(number), [])
    cloud_init = optional(object({
      username            = optional(string)
      ssh_authorized_keys = optional(list(string))
      ssh_port            = optional(number)
      extra_packages      = optional(list(string), [])
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
    condition = alltrue([
      for vm in var.vms : length(distinct([for volume in vm.volumes : volume.name])) == length(vm.volumes)
    ])
    error_message = "Volume names must be unique within each VM definition."
  }
}

variable "default_labels" {
  type        = map(string)
  description = "Module-level labels merged into each VM label map"
  default     = {}
}

variable "default_cloud_init" {
  type = object({
    username            = string
    ssh_authorized_keys = list(string)
    ssh_port            = optional(number, 22)
    extra_packages      = optional(list(string), [])
  })
  description = "Default generated cloud-init settings applied to VMs unless overridden per VM"
  default     = null
}
