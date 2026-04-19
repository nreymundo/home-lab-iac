variable "vm_name" {
  type        = string
  description = "Proxmox VM name and Ansible inventory hostname"
  default     = "openclaw"
}

variable "template_name" {
  type        = string
  description = "Packer template name to clone from"
  default     = "ubuntu-24.04-base"
}

variable "target_node" {
  type        = string
  description = "Proxmox node that will host the OpenClaw VM"
}

variable "vmid" {
  type        = number
  description = "Unique Proxmox VMID for the OpenClaw VM"
  validation {
    condition     = var.vmid >= 100
    error_message = "vmid must be 100 or greater."
  }
}

variable "ip_address" {
  type        = string
  description = "Static IPv4 address assigned to the OpenClaw VM"
}

variable "ip_prefix_len" {
  type        = number
  description = "CIDR prefix length for the VM address"
  default     = 24
  validation {
    condition     = var.ip_prefix_len >= 8 && var.ip_prefix_len <= 30
    error_message = "Prefix length must be between /8 and /30."
  }
}

variable "gateway_ip" {
  type        = string
  description = "Gateway IP address"
  default     = "192.168.10.1"
}

variable "dns_server" {
  type        = string
  description = "DNS resolver IP"
  default     = "192.168.10.1"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge to use"
  default     = "vmbr0"
}

variable "vlan_id" {
  type        = number
  description = "VLAN ID for the VM"
  default     = 10
}

variable "default_ci_user" {
  type        = string
  description = "cloud-init user configured on the VM"
  default     = "ubuntu"
}

variable "ansible_user" {
  type        = string
  description = "SSH user Ansible will use; defaults to the cloud-init user"
  default     = null
  nullable    = true
}

variable "ssh_keys_secret_id" {
  type        = string
  description = "Bitwarden Secrets Manager secret ID for SSH public keys"
  validation {
    condition     = length(trimspace(var.ssh_keys_secret_id)) > 0
    error_message = "ssh_keys_secret_id must be set."
  }
}

variable "vm_cores" {
  type        = number
  description = "CPU cores assigned to the VM"
  default     = 4
  validation {
    condition     = var.vm_cores >= 1 && var.vm_cores <= 32
    error_message = "CPU cores must be between 1 and 32."
  }
}

variable "vm_memory_mb" {
  type        = number
  description = "RAM in MB assigned to the VM"
  default     = 8192
  validation {
    condition     = var.vm_memory_mb >= 512
    error_message = "Memory must be at least 512 MB."
  }
}

variable "vm_balloon_mb" {
  type        = number
  description = "Minimum balloon memory in MB"
  default     = 1024
  validation {
    condition     = var.vm_balloon_mb >= 0 && var.vm_balloon_mb <= var.vm_memory_mb
    error_message = "Balloon memory must be between 0 and vm_memory_mb."
  }
}

variable "vm_disk_size_gb" {
  type        = number
  description = "Primary disk size in GB"
  default     = 64
  validation {
    condition     = var.vm_disk_size_gb >= 20
    error_message = "Disk size must be at least 20 GB."
  }
}

variable "storage_pool" {
  type        = string
  description = "Storage pool name for the VM disks"
  default     = "ssd-zfs"
}

variable "machine" {
  type        = string
  description = "Proxmox machine type"
  default     = "q35"
}

variable "proxmox_tags" {
  type        = list(string)
  description = "Additional Proxmox tags to apply to the VM"
  default     = []
}
