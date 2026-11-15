variable "vms" {
  description = "Unraid VM definitions and downstream inventory metadata."
  type = list(object({
    name               = string
    hostname           = optional(string)
    ansible_user       = string
    ip_address         = string
    vm_cores           = number
    vm_memory_mb       = number
    disk_path          = string
    disk_format        = optional(string, "qcow2")
    cloudinit_path     = optional(string)
    mac_address        = string
    smbios_uuid        = optional(string)
    generation_id      = optional(string)
    network_bridge     = optional(string, "br0")
    machine            = optional(string, "pc-q35-10.2")
    os_type            = optional(string, "linux")
    running            = optional(bool, true)
    start_at_node_boot = optional(bool, false)
    shutdown_timeout   = optional(number, 120)
  }))

  validation {
    condition     = length(distinct([for vm in var.vms : vm.name])) == length(var.vms)
    error_message = "Each VM name must be unique."
  }

  validation {
    condition     = alltrue([for vm in var.vms : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", vm.name))])
    error_message = "Each VM name must start with an alphanumeric character and contain only letters, numbers, underscores, dots, or hyphens."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vm_cores >= 1 && floor(vm.vm_cores) == vm.vm_cores && vm.vm_memory_mb >= 512 && floor(vm.vm_memory_mb) == vm.vm_memory_mb])
    error_message = "Each VM must have a positive integer core count and at least 512 MiB of memory in whole MiB."
  }

  validation {
    condition     = alltrue([for vm in var.vms : can(cidrnetmask("${vm.ip_address}/32"))])
    error_message = "Each VM ip_address must be a valid IPv4 address."
  }
}
