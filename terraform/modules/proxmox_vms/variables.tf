variable "ssh_public_keys_secret_id" {
  type        = string
  description = "Bitwarden Secrets Manager secret ID containing newline-delimited SSH public keys. Set to null to disable."
  default     = "9b5f1231-f792-4e85-96f1-b3c60002f839"
  nullable    = true
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "Additional SSH public keys to add to all VMs."
  default     = []

  validation {
    condition = alltrue([
      for public_key in var.ssh_public_keys :
      startswith(trimspace(public_key), "ssh-ed25519 ") ||
      startswith(trimspace(public_key), "ssh-rsa ") ||
      startswith(trimspace(public_key), "ecdsa-sha2-")
    ])
    error_message = "Each ssh_public_keys entry must look like an OpenSSH public key."
  }
}

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
    condition     = length(distinct([for vm in var.vms : vm.name])) == length(var.vms)
    error_message = "Each VM name must be unique."
  }

  validation {
    condition     = alltrue([for vm in var.vms : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", vm.name))])
    error_message = "Each VM name must start with an alphanumeric character and contain only letters, numbers, underscores, dots, or hyphens."
  }

  validation {
    condition     = length(distinct([for vm in var.vms : vm.vmid])) == length(var.vms)
    error_message = "Each VM vmid must be unique."
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
    condition     = alltrue([for vm in var.vms : can(cidrnetmask("${vm.ip_address}/${vm.ip_prefix_len}"))])
    error_message = "Each VM ip_address must be a valid IPv4 address for its ip_prefix_len."
  }

  validation {
    condition     = length(distinct([for vm in var.vms : vm.ip_address])) == length(var.vms)
    error_message = "Each VM ip_address must be unique."
  }

  validation {
    condition     = alltrue([for vm in var.vms : can(cidrnetmask("${vm.gateway_ip}/32"))])
    error_message = "Each VM gateway_ip must be a valid IPv4 address."
  }

  validation {
    condition     = alltrue([for vm in var.vms : can(cidrnetmask("${vm.dns_server}/32"))])
    error_message = "Each VM dns_server must be a valid IPv4 address."
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

  validation {
    condition     = alltrue([for vm in var.vms : !vm.secondary_disk_enabled || vm.secondary_disk_size_gb > 0])
    error_message = "Each VM with secondary_disk_enabled must set secondary_disk_size_gb greater than 0."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [
        for tag in vm.proxmox_tags : can(regex("^[A-Za-z0-9][A-Za-z0-9_.:-]*$", tag))
      ]
    ]))
    error_message = "Each VM proxmox_tags entry must start with an alphanumeric character and contain only letters, numbers, underscores, dots, colons, or hyphens."
  }
}
