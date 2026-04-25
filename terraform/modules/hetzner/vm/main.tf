locals {
  base_cloud_init_packages = ["fail2ban", "ufw"]

  normalized_default_cloud_init = var.default_cloud_init == null ? null : {
    username            = trimspace(var.default_cloud_init.username)
    ssh_authorized_keys = var.default_cloud_init.ssh_authorized_keys
    ssh_port            = coalesce(try(var.default_cloud_init.ssh_port, null), 22)
    extra_packages      = coalesce(try(var.default_cloud_init.extra_packages, null), [])
  }

  vms_by_name = {
    for vm in var.vms : vm.name => merge(vm, {
      cloud_init = (try(vm.cloud_init, null) == null && local.normalized_default_cloud_init == null) ? null : {
        username = trimspace(coalesce(
          try(vm.cloud_init.username, null),
          try(local.normalized_default_cloud_init.username, null),
          ""
        ))
        ssh_authorized_keys = coalesce(
          try(vm.cloud_init.ssh_authorized_keys, null),
          try(local.normalized_default_cloud_init.ssh_authorized_keys, null),
          []
        )
        ssh_port = coalesce(
          try(vm.cloud_init.ssh_port, null),
          try(local.normalized_default_cloud_init.ssh_port, null),
          22
        )
        extra_packages = distinct(concat(
          try(local.normalized_default_cloud_init.extra_packages, []),
          coalesce(try(vm.cloud_init.extra_packages, null), [])
        ))
      }
      firewall_ids = coalesce(vm.firewall_ids, [])
      labels       = merge(var.default_labels, coalesce(vm.labels, {}))
      user_data = try(vm.user_data, null) != null ? vm.user_data : (
        (try(vm.cloud_init, null) == null && local.normalized_default_cloud_init == null) ? null : join("", [
          "#cloud-config\n",
          yamlencode({
            users = [{
              name                = trimspace(coalesce(try(vm.cloud_init.username, null), try(local.normalized_default_cloud_init.username, null), ""))
              groups              = "users, admin"
              sudo                = "ALL=(ALL) NOPASSWD:ALL"
              shell               = "/bin/bash"
              ssh_authorized_keys = coalesce(try(vm.cloud_init.ssh_authorized_keys, null), try(local.normalized_default_cloud_init.ssh_authorized_keys, null), [])
            }]
            packages = distinct(concat(
              local.base_cloud_init_packages,
              distinct(concat(
                try(local.normalized_default_cloud_init.extra_packages, []),
                coalesce(try(vm.cloud_init.extra_packages, null), [])
              ))
            ))
            package_update  = true
            package_upgrade = true
            write_files = [{
              path = "/etc/ssh/sshd_config.d/ssh-hardening.conf"
              content = join("\n", [
                "PermitRootLogin no",
                "PasswordAuthentication no",
                format("Port %d", coalesce(try(vm.cloud_init.ssh_port, null), try(local.normalized_default_cloud_init.ssh_port, null), 22)),
                "KbdInteractiveAuthentication no",
                "ChallengeResponseAuthentication no",
                "MaxAuthTries 2",
                "AllowTcpForwarding no",
                "X11Forwarding no",
                "AllowAgentForwarding no",
                "AuthorizedKeysFile .ssh/authorized_keys",
                format("AllowUsers %s", trimspace(coalesce(try(vm.cloud_init.username, null), try(local.normalized_default_cloud_init.username, null), ""))),
                "",
              ])
            }]
            runcmd = [
              format("printf '[sshd]\\nenabled = true\\nport = ssh, %d\\nbanaction = iptables-multiport' > /etc/fail2ban/jail.local", coalesce(try(vm.cloud_init.ssh_port, null), try(local.normalized_default_cloud_init.ssh_port, null), 22)),
              "systemctl enable fail2ban",
              format("ufw allow %d", coalesce(try(vm.cloud_init.ssh_port, null), try(local.normalized_default_cloud_init.ssh_port, null), 22)),
              "ufw --force enable",
              "systemctl restart ssh",
            ]
          })
        ])
      )
      volumes = [
        for volume in coalesce(vm.volumes, []) : merge(volume, {
          labels = merge(
            merge(var.default_labels, coalesce(vm.labels, {})),
            coalesce(volume.labels, {})
          )
        })
      ]
      private_network = vm.private_network == null ? null : merge(vm.private_network, {
        alias_ips = coalesce(vm.private_network.alias_ips, [])
      })
    })
  }

  volumes_by_key = length(local.vms_by_name) == 0 ? {} : merge([
    for vm_name, vm in local.vms_by_name : {
      for volume in vm.volumes : format("%s/%s", vm_name, volume.name) => merge(volume, {
        key      = format("%s/%s", vm_name, volume.name)
        vm_name  = vm_name
        location = vm.location
        labels   = volume.labels
      })
    }
  ]...)
}

resource "hcloud_server" "vms" {
  for_each = local.vms_by_name

  name               = each.value.name
  server_type        = each.value.server_type
  image              = each.value.image
  location           = each.value.location
  ssh_keys           = length(each.value.ssh_key_ids) == 0 ? null : each.value.ssh_key_ids
  firewall_ids       = each.value.firewall_ids
  placement_group_id = each.value.placement_group_id
  labels             = each.value.labels
  backups            = each.value.backups
  user_data          = each.value.user_data
  delete_protection  = each.value.delete_protection
  rebuild_protection = each.value.rebuild_protection

  lifecycle {
    ignore_changes = [ssh_keys] # Hetzner treats ssh_keys changes as ForceNew after creation.

    precondition {
      condition = each.value.cloud_init == null || (
        length(trimspace(each.value.cloud_init.username)) > 0 &&
        length(each.value.cloud_init.ssh_authorized_keys) > 0
      )
      error_message = "Generated cloud-init requires a non-empty username and at least one ssh_authorized_key unless explicit user_data is provided."
    }
  }

  public_net {
    ipv4_enabled = each.value.enable_public_ipv4
    ipv6_enabled = each.value.enable_public_ipv6
  }
}

resource "hcloud_server_network" "private" {
  for_each = {
    for vm_name, vm in local.vms_by_name : vm_name => vm
    if vm.private_network != null
  }

  server_id  = hcloud_server.vms[each.key].id
  network_id = each.value.private_network.network_id
  ip         = each.value.private_network.ip
  alias_ips  = each.value.private_network.alias_ips
}

resource "hcloud_volume" "data" {
  for_each = local.volumes_by_key

  name     = each.value.name
  size     = each.value.size
  location = each.value.location
  format   = each.value.format
  labels   = each.value.labels
}

resource "hcloud_volume_attachment" "data" {
  for_each = local.volumes_by_key

  volume_id = hcloud_volume.data[each.key].id
  server_id = hcloud_server.vms[each.value.vm_name].id
  automount = each.value.automount
}
