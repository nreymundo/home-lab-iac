variable "ssh_keys" {
  type = map(object({
    name       = optional(string)
    public_key = string
    labels     = optional(map(string), {})
  }))
  description = "Hetzner SSH keys to create, keyed by a stable identifier"

  validation {
    condition     = alltrue([for ssh_key in values(var.ssh_keys) : length(trimspace(ssh_key.public_key)) > 0])
    error_message = "Each SSH key must define a non-empty public_key."
  }
}

variable "default_labels" {
  type        = map(string)
  description = "Module-level labels merged into each SSH key label map"
  default     = {}
}
