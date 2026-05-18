resource "local_file" "ansible_inventory" {
  filename        = abspath("${path.module}/../../../../ansible/inventories/llm.yml")
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    containers = module.proxmox_lxc.containers
  })
}
