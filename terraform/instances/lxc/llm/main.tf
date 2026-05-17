module "proxmox_lxc" {
  source = "../../../modules/proxmox_lxc"

  ssh_bootstrap_cluster_ssh_host = "root@192.168.1.4"

  containers = local.lxc_definitions
}
