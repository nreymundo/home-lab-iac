locals {
  vms_by_name = {
    for vm in var.vms : vm.name => merge(vm, {
      cloud_init   = local.cloud_init_by_vm_name[vm.name]
      firewall_ids = coalesce(vm.firewall_ids, [])
      labels       = merge(var.default_labels, coalesce(vm.labels, {}))
      user_data = local.generated_user_data_by_vm_name[vm.name]
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
