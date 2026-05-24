resource "local_file" "ansible_inventory" {
  filename        = abspath("${path.module}/../../../../ansible/inventories/llm.yml")
  file_permission = "0644"

  content = join("", [
    "---\n",
    yamlencode({
      all = {
        children = {
          llm_lxc = {
            hosts = {
              for container in module.proxmox_lxc.containers : container.name => {
                ansible_host = container.ip_address
                ansible_user = container.ansible_user
                ansible_port = 22
                guest_os     = "fedora"
              }
            }
          }
        }
      }
    })
  ])
}
