variable "vms" {
  type = list(object({
    name                        = string
    target_node                 = string
    vmid                        = number
    template_name               = optional(string, "ubuntu-24.04-base")
    ci_user                     = string
    ansible_user                = string
    ip_address                  = string
    ip_prefix_len               = optional(number, 24)
    gateway_ip                  = optional(string, "192.168.10.1")
    dns_server                  = optional(string, "192.168.10.1")
    network_bridge              = optional(string, "vmbr0")
    vlan_id                     = optional(number, 10)
    vm_cores                    = number
    vm_memory_mb                = number
    vm_balloon_mb               = number
    ballooning_enabled          = optional(bool)
    vm_disk_size_gb             = number
    storage_pool                = optional(string, "ssd-zfs")
    secondary_disk_enabled      = optional(bool, false)
    secondary_disk_storage_pool = optional(string)
    secondary_disk_size_gb      = optional(number, 0)
    proxmox_tags                = optional(list(string), [])
    machine                     = optional(string, "q35")
    pci_devices = optional(list(object({
      id     = string
      pcie   = optional(bool, true)
      rombar = optional(bool, true)
    })), [])
  }))
  description = "Normalized VM definitions to provision in Proxmox"

  validation {
    condition     = length(var.vms) > 0
    error_message = "At least one VM definition must be provided."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vmid >= 100])
    error_message = "Each VM vmid must be 100 or greater."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.ip_prefix_len >= 8 && vm.ip_prefix_len <= 30])
    error_message = "Each VM ip_prefix_len must be between /8 and /30."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vm_cores >= 1 && vm.vm_cores <= 32])
    error_message = "Each VM vm_cores value must be between 1 and 32."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vm_memory_mb >= 512])
    error_message = "Each VM vm_memory_mb value must be at least 512 MB."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vm_balloon_mb >= 0 && vm.vm_balloon_mb <= vm.vm_memory_mb])
    error_message = "Each VM vm_balloon_mb value must be between 0 and vm_memory_mb."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.vm_disk_size_gb >= 20])
    error_message = "Each VM vm_disk_size_gb value must be at least 20 GB."
  }

  validation {
    condition     = alltrue([for vm in var.vms : vm.secondary_disk_size_gb >= 0])
    error_message = "Each VM secondary_disk_size_gb value must be 0 or greater."
  }
}
