output "vms" {
  description = "VM metadata keyed by VM name for downstream consumers"

  value = {
    for vm_name, vm in local.vms_by_name : vm_name => {
      id                 = hcloud_server.vms[vm_name].id
      name               = hcloud_server.vms[vm_name].name
      ipv4_address       = hcloud_server.vms[vm_name].ipv4_address
      ipv6_address       = hcloud_server.vms[vm_name].ipv6_address
      status             = hcloud_server.vms[vm_name].status
      firewall_ids       = vm.firewall_ids
      private_network_id = vm.private_network == null ? null : vm.private_network.network_id
      volumes = {
        for volume in vm.volumes : volume.name => {
          id           = hcloud_volume.data[format("%s/%s", vm_name, volume.name)].id
          name         = hcloud_volume.data[format("%s/%s", vm_name, volume.name)].name
          size         = hcloud_volume.data[format("%s/%s", vm_name, volume.name)].size
          linux_device = hcloud_volume.data[format("%s/%s", vm_name, volume.name)].linux_device
          automount    = hcloud_volume_attachment.data[format("%s/%s", vm_name, volume.name)].automount
          server_id    = hcloud_volume_attachment.data[format("%s/%s", vm_name, volume.name)].server_id
        }
      }
    }
  }
}
