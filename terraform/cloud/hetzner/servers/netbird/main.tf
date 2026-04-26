data "bitwarden-secrets_secret" "ssh_public_keys" {
  id = local.ssh_public_keys_secret_id
}

data "terraform_remote_state" "firewall" {
  backend = "remote"

  config = {
    organization = "home-lab-iac"
    workspaces = {
      name = "hetzner-firewall"
    }
  }
}

module "vm" {
  source = "../../../../modules/hetzner/vm"

  default_labels     = local.default_labels
  default_cloud_init = local.default_cloud_init
  vms                = [local.vm]
}
