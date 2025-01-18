# VM variables
variable "proxmox_node" {
    type = string
    default = "pve1"
}

variable "qemu_agent" {
    type    = bool
    default = true
}

variable "cores" {
    type    = string
    default = "1"
}

variable "memory" {
    type    = string
    default = "2048"
}

# Proxmox connection variables
variable "proxmox_api_url" {
    type = string
}

variable "proxmox_api_token_id" {
    type = string
}

variable "proxmox_api_token_secret" {
    type = string
    sensitive = true
}

variable "proxmox_skip_tls_verify" {
    type    = bool
    default = true
}

# SSH connectivity
variable "ssh_username" {
    type = string
}

variable "ssh_public_key" {
    type = string
}

variable "ssh_private_key_file" {
    type = string
}

variable "local_http_address" {
    type = string
}