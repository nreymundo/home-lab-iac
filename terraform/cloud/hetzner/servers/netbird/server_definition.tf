locals {
  ssh_public_keys_secret_id = "9b5f1231-f792-4e85-96f1-b3c60002f839"

  default_labels = {
    managed_by = "terraform"
  }

  ssh_public_keys = compact([
    for line in split(
      "\n",
      replace(trimspace(data.bitwarden-secrets_secret.ssh_public_keys.value), "\r\n", "\n")
    ) : nonsensitive(trimspace(line))
  ])

  default_cloud_init = {
    username            = "netbird"
    ssh_authorized_keys = local.ssh_public_keys
    ssh_port            = 2222
    extra_packages      = []
  }

  vm_definition = [{
    name        = "netbird"
    server_type = "cx23"
    image       = "ubuntu-24.04"
    location    = "fsn1"
    firewall_ids = [
      for firewall_key in ["ssh"] : data.terraform_remote_state.firewall.outputs.firewall_ids[firewall_key]
    ]
    labels = {
      os          = "ubuntu"
      environment = "production"
    }
    backups            = false
    enable_public_ipv4 = true
    enable_public_ipv6 = true
    volumes            = []
  }]
}
