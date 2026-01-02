locals {
  node_ip_subnet      = "${join(".", slice(split(".", var.node_ip_start), 0, 3))}.0/${var.ip_prefix_len}"
  node_ip_start_octet = tonumber(split(".", var.node_ip_start)[3])
  node_count          = length(var.nodes)
  ssh_public_keys_list = compact(
    split(
      "\n",
      replace(trimspace(data.bitwarden-secrets_secret.ssh_public_keys.value), "\r\n", "\n")
    )
  )
}

resource "proxmox_vm_qemu" "k3s_nodes" {
  count = local.node_count

  name        = "k3s-node-${format("%02d", count.index + 1)}"
  target_node = coalesce(try(var.nodes[count.index].target_node, null), element(var.proxmox_nodes, count.index % length(var.proxmox_nodes)))
  vmid        = var.node_vmid_start + count.index

  clone      = coalesce(try(var.nodes[count.index].template_name, null), var.template_name)
  full_clone = true

  scsihw = "virtio-scsi-single"

  cpu {
    type    = "host"
    cores   = var.vm_cores
    sockets = 1
  }

  memory = var.vm_memory_mb

  os_type = "cloud-init"
  ciuser  = coalesce(try(var.nodes[count.index].ci_user, null), var.default_ci_user)
  sshkeys = join("\n", local.ssh_public_keys_list)


  network {
    id     = 0
    model  = "virtio"
    bridge = var.network_bridge
    tag    = var.vlan_id
  }

  ipconfig0 = "ip=${cidrhost(local.node_ip_subnet, local.node_ip_start_octet + count.index)}/${var.ip_prefix_len},gw=${var.gateway_ip}"

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
      dynamic "scsi1" {
        for_each = var.secondary_disk_enabled ? [1] : []
        content {
          disk {
            storage    = var.secondary_disk_storage_pool
            size       = "${var.secondary_disk_size_gb}G"
            cache      = "writeback"
            iothread   = true
            discard    = true
            emulatessd = true
          }
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

  boot  = "order=scsi0"
  agent = 1
  tags  = "terraform,k3s-node"

  lifecycle {
    ignore_changes = [
      cipassword,
      startup_shutdown
    ]
  }
}

# -----------------------------------------------------------------------------
# Ansible Inventory Generation
# -----------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventories/k3s-nodes.yml"

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    nodes = [
      for idx in range(local.node_count) : {
        name         = "k3s-node-${format("%02d", idx + 1)}"
        ip           = cidrhost(local.node_ip_subnet, local.node_ip_start_octet + idx)
        ansible_user = coalesce(try(var.nodes[idx].ansible_user, null), coalesce(try(var.nodes[idx].ci_user, null), var.default_ci_user))
        node_os      = coalesce(try(var.nodes[idx].ci_user, null), var.default_ci_user)
      }
    ]
  })
}
