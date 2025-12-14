# ------------------------------------------------------------------------------
# Packer variables for the Proxmox Ubuntu 24.04 Base Image
# ------------------------------------------------------------------------------

# --- Proxmox API Configuration ---

# --- Proxmox API Credentials (Sensitive) ---
# These variables should be provided via environment variables for security.
# Example:
# export PKR_VAR_proxmox_api_url="https://url:port/api2/json"
# export PKR_VAR_proxmox_api_token_id="your-token-id"
# export PKR_VAR_proxmox_api_token_secret="your-secret"

variable "proxmox_api_url" {
  type        = string
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


variable "http_directory" {
  type        = string
  default     = "http"
  description = "Directory served by Packer's HTTP server for autoinstall seed files."
}

variable "ssh_private_key_file" {
  type        = string
  default     = "~/.ssh/id_ed25519"
  description = "Private SSH key used by Packer to connect to the guest."
}
