variable "template_name" {
  type        = string
  description = "Name of the immutable HAOS template to clone. Changing this value never replaces the protected live VM."
  default     = "haos-18.2"
  nullable    = false

  validation {
    condition     = trimspace(var.template_name) == var.template_name && can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.template_name))
    error_message = "template_name must be a non-empty Proxmox name containing only letters, numbers, dots, underscores, and hyphens."
  }
}

variable "vm_state" {
  type        = string
  description = "Desired power state for vm-haos. Set to stopped only for maintenance."
  default     = "running"
  nullable    = false

  validation {
    condition     = contains(["running", "stopped"], var.vm_state)
    error_message = "vm_state must be either running or stopped."
  }
}
