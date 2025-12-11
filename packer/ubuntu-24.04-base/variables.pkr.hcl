# ------------------------------------------------------------------------------
# Packer variables for the Proxmox Ubuntu 24.04 Base Image
# ------------------------------------------------------------------------------

# --- Proxmox API Configuration ---

variable "proxmox_api_url" {
  type        = string
  default     = "https://192.168.1.4:8006/api2/json"
  description = "The URL for the Proxmox VE API."
}

variable "proxmox_api_token_id" {
  type        = string
  sensitive   = true
  description = "The ID of the Proxmox API token."
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "The secret of the Proxmox API token."
}

# --- ISO Configuration ---

variable "iso_name" {
  type        = string
  default     = "ubuntu-24.04.3-live-server-amd64.iso"
  description = "The name of the ISO file to use (must be available on the Proxmox storage)."
}

variable "iso_storage_pool" {
  type        = string
  default     = "unraid"
  description = "The Proxmox storage pool where the ISO is located."
}

# --- SSH Configuraton ---

variable "ssh_username" {
  type        = string
  description = "The SSH username to connect with"
}

variable "ssh_password" {
  type        = string
  description = "The SSH password to connect with"
}
