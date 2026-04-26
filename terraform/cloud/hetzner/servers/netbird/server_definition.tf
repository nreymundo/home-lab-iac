locals {
  ssh_public_keys_secret_id = "9b5f1231-f792-4e85-96f1-b3c60002f839"

  default_ansible_connection = {
    user = "netbird"
    port = 2222
  }

  default_labels = {
    managed_by = "terraform"
  }

  netbird_firewall_ids = [
    for firewall_key in ["ssh", "http", "https", "netbird-udp"] : data.terraform_remote_state.firewall.outputs.firewall_ids[firewall_key]
  ]

  netbird_ufw_rules = [
    for rule in flatten([
      for firewall_key in ["http", "https", "netbird-udp"] : data.terraform_remote_state.firewall.outputs.firewalls[firewall_key].rules
      ]) : {
      port     = rule.port
      protocol = rule.protocol
    }
    if rule.direction == "in" && contains(["tcp", "udp"], rule.protocol) && try(rule.port, null) != null && rule.port != "any"
  ]

  ssh_public_keys = compact([
    for line in split(
      "\n",
      replace(trimspace(data.bitwarden-secrets_secret.ssh_public_keys.value), "\r\n", "\n")
    ) : nonsensitive(trimspace(line))
  ])

  # Module-level baseline for generated cloud-init. Individual VM definitions can
  # still add or override fields via vm.cloud_init.
  default_cloud_init = {
    username            = local.default_ansible_connection.user
    ssh_authorized_keys = local.ssh_public_keys
    ssh_port            = local.default_ansible_connection.port
    extra_packages      = []
  }

  netbird_vm = {
    name         = "netbird"
    ansible_user = local.default_ansible_connection.user
    ansible_port = local.default_ansible_connection.port
    server_type  = "cx23"
    image        = "ubuntu-24.04"
    location     = "fsn1"
    # Per-VM cloud_init is merged with local.default_cloud_init by the Hetzner VM
    # module; here it only adds NetBird-specific UFW rules.
    cloud_init = {
      ufw_rules = local.netbird_ufw_rules
    }
    firewall_ids = local.netbird_firewall_ids
    labels = {
      os          = "ubuntu"
      environment = "production"
    }
    backups            = false
    enable_public_ipv4 = true
    enable_public_ipv6 = true
    volumes            = []
  }

  ansible_inventory_connection_by_vm_name = {
    (local.netbird_vm.name) = {
      ansible_user = try(local.netbird_vm.user_data, null) != null ? try(local.netbird_vm.ansible_user, null) : coalesce(try(local.netbird_vm.ansible_user, null), try(local.netbird_vm.cloud_init.username, null), local.default_cloud_init.username)
      ansible_port = try(local.netbird_vm.user_data, null) != null ? try(local.netbird_vm.ansible_port, null) : coalesce(try(local.netbird_vm.ansible_port, null), try(local.netbird_vm.cloud_init.ssh_port, null), local.default_cloud_init.ssh_port)
    }
  }
}
