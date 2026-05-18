output "containers" {
  description = "Normalized LXC metadata for downstream inventory generation."
  value = [
    for name, container in local.container_by_name : {
      name         = container.name
      hostname     = container.hostname
      target_node  = container.target_node
      vmid         = container.vmid
      ip_address   = try(container.ip_address, null)
      ansible_user = container.ansible_user
      tags         = container.tags
      id           = proxmox_virtual_environment_container.this[name].id
    }
  ]
}

output "template_file_ids" {
  description = "Template file IDs used by each LXC container."
  value = {
    for name, container in local.container_by_name :
    name => container.template_key == null ? container.template_file_id : proxmox_download_file.lxc_image[name].id
  }
}
