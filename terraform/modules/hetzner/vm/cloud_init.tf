locals {
  base_cloud_init_packages = ["fail2ban", "ufw"]

  normalized_default_cloud_init = var.default_cloud_init == null ? null : {
    username            = trimspace(var.default_cloud_init.username)
    ssh_authorized_keys = var.default_cloud_init.ssh_authorized_keys
    ssh_port            = coalesce(try(var.default_cloud_init.ssh_port, null), 22)
    extra_packages      = coalesce(try(var.default_cloud_init.extra_packages, null), [])
  }

  cloud_init_by_vm_name = {
    for vm in var.vms : vm.name => ((try(vm.cloud_init, null) == null && local.normalized_default_cloud_init == null) ? null : {
      username = trimspace(coalesce(
        try(vm.cloud_init.username, null),
        try(local.normalized_default_cloud_init.username, null),
        ""
      ))
      ssh_authorized_keys = coalesce(
        try(vm.cloud_init.ssh_authorized_keys, null),
        try(local.normalized_default_cloud_init.ssh_authorized_keys, null),
        []
      )
      ssh_port = coalesce(
        try(vm.cloud_init.ssh_port, null),
        try(local.normalized_default_cloud_init.ssh_port, null),
        22
      )
      extra_packages = distinct(concat(
        try(local.normalized_default_cloud_init.extra_packages, []),
        coalesce(try(vm.cloud_init.extra_packages, null), [])
      ))
    })
  }

  generated_user_data_by_vm_name = {
    for vm in var.vms : vm.name => (try(vm.user_data, null) != null ? vm.user_data : (
      local.cloud_init_by_vm_name[vm.name] == null ? null : join("", [
        "#cloud-config\n",
        yamlencode({
          users = [{
            name                = local.cloud_init_by_vm_name[vm.name].username
            groups              = "users, admin"
            sudo                = "ALL=(ALL) NOPASSWD:ALL"
            shell               = "/bin/bash"
            ssh_authorized_keys = local.cloud_init_by_vm_name[vm.name].ssh_authorized_keys
          }]
          packages = distinct(concat(
            local.base_cloud_init_packages,
            local.cloud_init_by_vm_name[vm.name].extra_packages
          ))
          package_update  = true
          package_upgrade = true
          write_files = [{
            path = "/etc/ssh/sshd_config.d/ssh-hardening.conf"
            content = join("\n", [
              "PermitRootLogin no",
              "PasswordAuthentication no",
              format("Port %d", local.cloud_init_by_vm_name[vm.name].ssh_port),
              "KbdInteractiveAuthentication no",
              "ChallengeResponseAuthentication no",
              "MaxAuthTries 2",
              "AllowTcpForwarding no",
              "X11Forwarding no",
              "AllowAgentForwarding no",
              "AuthorizedKeysFile .ssh/authorized_keys",
              format("AllowUsers %s", local.cloud_init_by_vm_name[vm.name].username),
              "",
            ])
          }]
          runcmd = [
            format("printf '[sshd]\\nenabled = true\\nport = ssh, %d\\nbanaction = iptables-multiport' > /etc/fail2ban/jail.local", local.cloud_init_by_vm_name[vm.name].ssh_port),
            "systemctl enable fail2ban",
            format("ufw allow %d", local.cloud_init_by_vm_name[vm.name].ssh_port),
            "ufw --force enable",
            "systemctl restart ssh",
          ]
        })
      ])
    ))
  }
}
