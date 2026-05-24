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

  validation {
    condition = alltrue([
      for key, ssh_key in var.ssh_keys :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.@+-]*$", coalesce(ssh_key.name, key)))
    ])
    error_message = "Each SSH key name must start with an alphanumeric character and contain only provider-safe characters."
  }

  validation {
    condition = alltrue([
      for ssh_key in values(var.ssh_keys) :
      startswith(trimspace(ssh_key.public_key), "ssh-ed25519 ") ||
      startswith(trimspace(ssh_key.public_key), "ssh-rsa ") ||
      startswith(trimspace(ssh_key.public_key), "ecdsa-sha2-")
    ])
    error_message = "Each SSH key public_key must look like an OpenSSH public key."
  }

  validation {
    condition = alltrue(flatten([
      for ssh_key in values(var.ssh_keys) : [
        for label_key, label_value in ssh_key.labels :
        can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", label_key)) && length(label_value) <= 63
      ]
    ]))
    error_message = "Each SSH key label key must be provider-safe and each label value must be 63 characters or fewer."
  }
}

variable "default_labels" {
  type        = map(string)
  description = "Module-level labels merged into each SSH key label map"
  default     = {}

  validation {
    condition = alltrue([
      for label_key, label_value in var.default_labels :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", label_key)) && length(label_value) <= 63
    ])
    error_message = "Each default label key must be provider-safe and each label value must be 63 characters or fewer."
  }
}
