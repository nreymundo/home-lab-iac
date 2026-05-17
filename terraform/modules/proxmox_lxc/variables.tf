variable "ssh_public_keys_secret_id" {
  type        = string
  description = "Bitwarden Secrets Manager secret ID containing newline-delimited SSH public keys. Set to null to disable."
  default     = "9b5f1231-f792-4e85-96f1-b3c60002f839"
  nullable    = true
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "Additional SSH public keys to add to all containers."
  default     = []
}

variable "containers" {
  type = list(object({
    name        = string
    target_node = string
    vmid        = number

    ansible_user = optional(string, "root")
    description  = optional(string, "Managed by Terraform")
    hostname     = optional(string)

    template_file_id = optional(string)
    image = optional(object({
      url                 = string
      datastore_id        = optional(string, "local")
      file_name           = optional(string)
      checksum            = optional(string)
      checksum_algorithm  = optional(string)
      upload_timeout      = optional(number)
      overwrite           = optional(bool)
      overwrite_unmanaged = optional(bool)
      verify              = optional(bool)
    }))
    os_type = optional(string, "unmanaged")

    unprivileged  = optional(bool, true)
    start_on_boot = optional(bool, true)
    started       = optional(bool, true)
    protection    = optional(bool, false)
    tags          = optional(list(string), [])

    cpu_cores        = number
    cpu_architecture = optional(string, "amd64")
    cpu_limit        = optional(number, 0)
    cpu_units        = optional(number, 1024)

    memory_mb = number
    swap_mb   = optional(number, 0)

    rootfs_datastore_id = optional(string, "ssd-zfs")
    rootfs_size_gb      = number
    rootfs_mount_options = optional(list(string), [
      "noatime",
    ])

    ip_address    = optional(string)
    ip_prefix_len = optional(number, 24)
    gateway_ip    = optional(string, "192.168.10.1")
    dns_servers   = optional(list(string), ["192.168.10.1"])
    dns_domain    = optional(string)

    network = optional(object({
      name         = optional(string, "eth0")
      bridge       = optional(string, "vmbr0")
      enabled      = optional(bool, true)
      firewall     = optional(bool, false)
      host_managed = optional(bool, false)
      vlan_id      = optional(number)
      mac_address  = optional(string)
      mtu          = optional(number)
      rate_limit   = optional(number)
    }), {})

    features = optional(object({
      nesting = optional(bool, false)
      fuse    = optional(bool, false)
      keyctl  = optional(bool, false)
      mknod   = optional(bool, false)
      mount   = optional(list(string), [])
    }), {})

    mount_points = optional(list(object({
      path          = string
      volume        = string
      size          = optional(string)
      read_only     = optional(bool)
      backup        = optional(bool)
      replicate     = optional(bool)
      shared        = optional(bool)
      acl           = optional(bool)
      quota         = optional(bool)
      mount_options = optional(list(string))
    })), [])

    device_passthrough = optional(list(object({
      path       = string
      deny_write = optional(bool)
      uid        = optional(number)
      gid        = optional(number)
      mode       = optional(string)
    })), [])

    idmaps = optional(list(object({
      type         = string
      container_id = number
      host_id      = number
      size         = number
    })), [])

    environment_variables = optional(map(string), {})
    ssh_public_keys       = optional(list(string), [])

    startup = optional(object({
      order      = string
      up_delay   = optional(string)
      down_delay = optional(string)
    }))

    wait_for_ip = optional(object({
      ipv4 = optional(bool, false)
      ipv6 = optional(bool, false)
    }))
  }))
  description = "LXC container definitions to provision in Proxmox."

  validation {
    condition     = length(var.containers) > 0
    error_message = "At least one LXC container definition must be provided."
  }

  validation {
    condition     = alltrue([for container in var.containers : container.vmid >= 100])
    error_message = "Each LXC vmid must be 100 or greater."
  }

  validation {
    condition = alltrue([
      for container in var.containers :
      try(container.template_file_id, null) != null || try(container.image.url, null) != null
    ])
    error_message = "Each LXC must set either template_file_id or image.url."
  }

  validation {
    condition = alltrue([
      for container in var.containers :
      !(try(container.template_file_id, null) != null && try(container.image.url, null) != null)
    ])
    error_message = "Each LXC must set only one of template_file_id or image.url."
  }

  validation {
    condition     = alltrue([for container in var.containers : container.ip_prefix_len >= 8 && container.ip_prefix_len <= 30])
    error_message = "Each LXC ip_prefix_len must be between /8 and /30."
  }

  validation {
    condition     = alltrue([for container in var.containers : container.cpu_cores >= 1 && container.cpu_cores <= 64])
    error_message = "Each LXC cpu_cores value must be between 1 and 64."
  }

  validation {
    condition     = alltrue([for container in var.containers : container.memory_mb >= 128])
    error_message = "Each LXC memory_mb value must be at least 128 MB."
  }

  validation {
    condition     = alltrue([for container in var.containers : container.swap_mb >= 0])
    error_message = "Each LXC swap_mb value must be 0 or greater."
  }

  validation {
    condition     = alltrue([for container in var.containers : container.rootfs_size_gb >= 1])
    error_message = "Each LXC rootfs_size_gb value must be at least 1 GB."
  }
}
