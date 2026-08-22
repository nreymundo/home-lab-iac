variable "emqx_template_file_id" {
  type        = string
  description = "Shared Proxmox template used for the EMQX LXC."
  default     = "unraid:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "emqx_target_node" {
  type        = string
  description = "Proxmox node that hosts the EMQX LXC."
  default     = "pve1"
}
