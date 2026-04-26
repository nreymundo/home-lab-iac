locals {
  ansible_inventory_vms = {
    for vm_name in sort(keys(module.vm.vms)) : vm_name => {
      id           = nonsensitive(module.vm.vms[vm_name].id)
      name         = nonsensitive(module.vm.vms[vm_name].name)
      ipv4_address = nonsensitive(module.vm.vms[vm_name].ipv4_address)
      ipv6_address = nonsensitive(module.vm.vms[vm_name].ipv6_address)
      status       = nonsensitive(module.vm.vms[vm_name].status)
      ansible_user = nonsensitive(module.vm.vms[vm_name].ansible_user)
      ansible_port = nonsensitive(module.vm.vms[vm_name].ansible_port)
      firewall_ids = nonsensitive(module.vm.vms[vm_name].firewall_ids)
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../../../../../ansible/inventories/public-vps.local.yml")

  lifecycle {
    precondition {
      condition     = length(local.ansible_inventory_vms) > 0
      error_message = "At least one Hetzner VM must be defined to generate the public_vps Ansible inventory."
    }

    precondition {
      condition = alltrue([
        for vm in values(local.ansible_inventory_vms) : vm.ipv4_address != null && vm.ansible_user != null && vm.ansible_port != null
      ])
      error_message = "Each generated Hetzner VM inventory entry requires ipv4_address, ansible_user, and ansible_port."
    }
  }

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    nodes = [
      for vm_name in sort(keys(local.ansible_inventory_vms)) : {
        name         = local.ansible_inventory_vms[vm_name].name
        ip           = local.ansible_inventory_vms[vm_name].ipv4_address
        ansible_user = local.ansible_inventory_vms[vm_name].ansible_user
        ansible_port = local.ansible_inventory_vms[vm_name].ansible_port
      }
    ]
  })
}
