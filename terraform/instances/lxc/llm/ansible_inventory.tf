resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../../../../ansible/inventories/llm.yml")

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    containers = module.proxmox_lxc.containers
  })
}
