# Environment inputs:
# - Terraform variables: TF_VAR_ssh_public_keys

# SSH Public Keys - DEPRECATED: Now retrieved from Bitwarden Secrets Manager
# This variable is kept for backward compatibility but is not used
variable "ssh_public_keys" {
  type        = list(string)
  description = "[DEPRECATED] List of public SSH keys to inject into VMs. Keys are now retrieved from Bitwarden Secrets Manager."
  default     = []
}

# Template Configuration
variable "template_name" {
  type        = string
  description = "Packer template name to clone from"
  default     = "ubuntu-24.04-base"
}

# Network Configuration
variable "ip_prefix_len" {
  type        = number
  description = "CIDR prefix length for node addresses"
  default     = 24
  validation {
    condition     = var.ip_prefix_len >= 8 && var.ip_prefix_len <= 30
    error_message = "Prefix length must be between /8 and /30."
  }
}

variable "vlan_id" {
  type        = number
  description = "VLAN ID for nodes"
  default     = 10
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

# Node Configuration
variable "node_count" {
  type        = number
  description = "Number of K3s node VMs to create"
  default     = 2
  validation {
    condition     = var.node_count >= 1
    error_message = "At least one node is required."
  }
}

variable "node_ip_start" {
  type        = string
  description = "Starting IP address for the first node VM. It will be incremented for subsequent nodes."
  default     = "192.168.10.50"
}

variable "node_vmid_start" {
  type        = number
  description = "Starting VMID for node VMs"
  default     = 200
  validation {
    condition     = var.node_vmid_start >= 100
    error_message = "Node VMID must be 100 or greater."
  }
}

# VM Configuration
variable "vm_cores" {
  type        = number
  description = "CPU cores per node VM"
  default     = 8
  validation {
    condition     = var.vm_cores >= 1 && var.vm_cores <= 32
    error_message = "CPU cores must be between 1 and 32."
  }
}

variable "vm_memory_mb" {
  type        = number
  description = "RAM in MB per node VM"
  default     = 8192
  validation {
    condition     = var.vm_memory_mb >= 512
    error_message = "Memory must be at least 512 MB."
  }
}

variable "vm_disk_size_gb" {
  type        = number
  description = "Disk size in GB per node VM"
  default     = 32
  validation {
    condition     = var.vm_disk_size_gb >= 20
    error_message = "Disk size must be at least 20 GB."
  }
}

variable "storage_pool" {
  type        = string
  description = "Storage pool name (ssd-zfs on each node)"
  default     = "ssd-zfs"
}

# Secondary Disk Configuration
variable "secondary_disk_enabled" {
  type        = bool
  description = "Enable creation of secondary vdisk"
  default     = true
}

variable "secondary_disk_storage_pool" {
  type        = string
  description = "Storage pool for secondary vdisk"
  default     = "ssd-zfs"
}

variable "secondary_disk_size_gb" {
  type        = number
  description = "Size in GB for secondary vdisk"
  default     = 200
  validation {
    condition     = var.secondary_disk_size_gb >= 0
    error_message = "Secondary disk size must be 0 or greater."
  }
}

# Proxmox Nodes
variable "proxmox_nodes" {
  type        = list(string)
  description = "List of Proxmox nodes for deployment. Nodes will be distributed across these nodes."
  default     = ["pve1", "pve2"]
  validation {
    condition     = length(var.proxmox_nodes) > 0
    error_message = "At least one Proxmox node must be specified."
  }
}
