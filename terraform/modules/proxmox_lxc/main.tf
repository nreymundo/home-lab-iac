data "bitwarden-secrets_secret" "ssh_public_keys" {
  count = var.ssh_public_keys_secret_id == null ? 0 : 1

  id = var.ssh_public_keys_secret_id
}

locals {
  bitwarden_ssh_public_keys = var.ssh_public_keys_secret_id == null ? [] : compact(
    split(
      "\n",
      replace(trimspace(data.bitwarden-secrets_secret.ssh_public_keys[0].value), "\r\n", "\n")
    )
  )

  base_ssh_public_keys = distinct(concat(
    local.bitwarden_ssh_public_keys,
    var.ssh_public_keys
  ))

  normalized_containers = [
    for container in var.containers : merge(container, {
      hostname        = coalesce(try(container.hostname, null), container.name)
      tags            = distinct(concat(["terraform", "lxc"], try(container.tags, [])))
      template_key    = try(container.image.url, null) == null ? null : container.name
      ssh_public_keys = distinct(concat(local.base_ssh_public_keys, try(container.ssh_public_keys, [])))
    })
  ]

  container_by_name = {
    for container in local.normalized_containers : container.name => container
  }

  image_downloads = {
    for container in local.normalized_containers : container.name => container.image
    if container.template_key != null
  }
}

resource "proxmox_download_file" "lxc_image" {
  for_each = local.image_downloads

  content_type        = "vztmpl"
  datastore_id        = each.value.datastore_id
  node_name           = local.container_by_name[each.key].target_node
  url                 = each.value.url
  file_name           = try(each.value.file_name, null)
  checksum            = try(each.value.checksum, null)
  checksum_algorithm  = try(each.value.checksum_algorithm, null)
  upload_timeout      = try(each.value.upload_timeout, null)
  overwrite           = try(each.value.overwrite, null)
  overwrite_unmanaged = try(each.value.overwrite_unmanaged, null)
  verify              = try(each.value.verify, null)
}

resource "proxmox_virtual_environment_container" "this" {
  for_each = local.container_by_name

  description   = each.value.description
  node_name     = each.value.target_node
  vm_id         = each.value.vmid
  unprivileged  = each.value.unprivileged
  start_on_boot = each.value.start_on_boot
  started       = each.value.started
  protection    = each.value.protection
  tags          = each.value.tags

  cpu {
    architecture = each.value.cpu_architecture
    cores        = each.value.cpu_cores
    limit        = each.value.cpu_limit
    units        = each.value.cpu_units
  }

  memory {
    dedicated = each.value.memory_mb
    swap      = each.value.swap_mb
  }

  disk {
    datastore_id  = each.value.rootfs_datastore_id
    size          = each.value.rootfs_size_gb
    mount_options = each.value.rootfs_mount_options
  }

  initialization {
    hostname = each.value.hostname

    dns {
      domain  = each.value.dns_domain
      servers = each.value.dns_servers
    }

    ip_config {
      ipv4 {
        address = try(each.value.ip_address, null) == null ? "dhcp" : "${each.value.ip_address}/${each.value.ip_prefix_len}"
        gateway = try(each.value.ip_address, null) == null ? null : each.value.gateway_ip
      }
    }

    user_account {
      keys = each.value.ssh_public_keys
    }
  }

  network_interface {
    name         = each.value.network.name
    bridge       = each.value.network.bridge
    enabled      = each.value.network.enabled
    firewall     = each.value.network.firewall
    host_managed = each.value.network.host_managed
    vlan_id      = try(each.value.network.vlan_id, null)
    mac_address  = try(each.value.network.mac_address, null)
    mtu          = try(each.value.network.mtu, null)
    rate_limit   = try(each.value.network.rate_limit, null)
  }

  operating_system {
    template_file_id = each.value.template_key == null ? each.value.template_file_id : proxmox_download_file.lxc_image[each.key].id
    type             = each.value.os_type
  }

  features {
    nesting = each.value.features.nesting
    fuse    = each.value.features.fuse
    keyctl  = each.value.features.keyctl
    mknod   = each.value.features.mknod
    mount   = each.value.features.mount
  }

  dynamic "mount_point" {
    for_each = {
      for idx, mount_point in each.value.mount_points : idx => mount_point
    }

    content {
      path          = mount_point.value.path
      volume        = mount_point.value.volume
      size          = try(mount_point.value.size, null)
      read_only     = try(mount_point.value.read_only, null)
      backup        = try(mount_point.value.backup, null)
      replicate     = try(mount_point.value.replicate, null)
      shared        = try(mount_point.value.shared, null)
      acl           = try(mount_point.value.acl, null)
      quota         = try(mount_point.value.quota, null)
      mount_options = try(mount_point.value.mount_options, null)
    }
  }

  dynamic "device_passthrough" {
    for_each = {
      for idx, device in each.value.device_passthrough : idx => device
    }

    content {
      path       = device_passthrough.value.path
      deny_write = try(device_passthrough.value.deny_write, null)
      uid        = try(device_passthrough.value.uid, null)
      gid        = try(device_passthrough.value.gid, null)
      mode       = try(device_passthrough.value.mode, null)
    }
  }

  dynamic "idmap" {
    for_each = {
      for idx, idmap in each.value.idmaps : idx => idmap
    }

    content {
      type         = idmap.value.type
      container_id = idmap.value.container_id
      host_id      = idmap.value.host_id
      size         = idmap.value.size
    }
  }

  dynamic "startup" {
    for_each = each.value.startup == null ? [] : [each.value.startup]

    content {
      order      = startup.value.order
      up_delay   = try(startup.value.up_delay, null)
      down_delay = try(startup.value.down_delay, null)
    }
  }

  dynamic "wait_for_ip" {
    for_each = each.value.wait_for_ip == null ? [] : [each.value.wait_for_ip]

    content {
      ipv4 = wait_for_ip.value.ipv4
      ipv6 = wait_for_ip.value.ipv6
    }
  }

  environment_variables = each.value.environment_variables
}
