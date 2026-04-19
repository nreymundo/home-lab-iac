resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../../../ansible/inventories/openclaw.yml")

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    name         = module.proxmox_vms.vms[0].name
    ip           = module.proxmox_vms.vms[0].ip_address
    ansible_user = module.proxmox_vms.vms[0].ansible_user
    node_os      = module.proxmox_vms.vms[0].ci_user
  })
}
