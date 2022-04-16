module "vm" {
  source            = "../../terraform/modules/proxmox-vm"

  vm_name           = "wireguard"
  vm_cpu_type       = "host"
  proxmox_host      = var.proxmox_host
  ansible_playbook  = "./ansible-bootstrap.yml"
}

variable "proxmox_host" {
}