locals {
  ci_user                = var.default_ci_user
  inventory_ansible_user = coalesce(var.ansible_user, local.ci_user)
  ssh_public_keys_list = compact(
    split(
      "\n",
      replace(trimspace(data.bitwarden-secrets_secret.ssh_public_keys.value), "\r\n", "\n")
    )
  )
  proxmox_tags = join(",", distinct(concat(["terraform"], var.proxmox_tags)))
}

resource "proxmox_vm_qemu" "openclaw" {
  name        = var.vm_name
  target_node = var.target_node
  vmid        = var.vmid

  clone      = var.template_name
  full_clone = true

  scsihw = "virtio-scsi-single"

  cpu {
    type    = "host"
    cores   = var.vm_cores
    sockets = 1
  }

  memory  = var.vm_memory_mb
  balloon = var.vm_balloon_mb

  os_type = "cloud-init"
  ciuser  = local.ci_user
  sshkeys = join("\n", local.ssh_public_keys_list)

  network {
    id     = 0
    model  = "virtio"
    bridge = var.network_bridge
    tag    = var.vlan_id
  }

  ipconfig0 = "ip=${var.ip_address}/${var.ip_prefix_len},gw=${var.gateway_ip}"

  nameserver = var.dns_server

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = var.storage_pool
          size       = var.vm_disk_size_gb
          cache      = "writeback"
          iothread   = true
          discard    = true
          emulatessd = true
        }
      }
    }
    ide {
      ide3 {
        cloudinit {
          storage = var.storage_pool
        }
      }
    }
  }

  boot               = "order=scsi0"
  start_at_node_boot = true
  agent              = 1
  tags               = local.proxmox_tags
  machine            = var.machine

  lifecycle {
    ignore_changes = [
      cipassword,
      startup_shutdown,
    ]
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventories/openclaw.yml"

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    name         = var.vm_name
    ip           = var.ip_address
    ansible_user = local.inventory_ansible_user
    node_os      = local.ci_user
  })
}
