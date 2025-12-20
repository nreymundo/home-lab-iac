locals {
  node_ip_subnet      = "${join(".", slice(split(".", var.node_ip_start), 0, 3))}.0/${var.ip_prefix_len}"
  node_ip_start_octet = tonumber(split(".", var.node_ip_start)[3])
}

resource "proxmox_vm_qemu" "k3s_nodes" {
  count = var.node_count

  name        = "k3s-node-${format("%02d", count.index + 1)}"
  target_node = element(var.proxmox_nodes, count.index % length(var.proxmox_nodes))
  vmid        = var.node_vmid_start + count.index

  clone      = var.template_name
  full_clone = true

  scsihw = "virtio-scsi-single"

  cpu {
    type    = "host"
    cores   = var.vm_cores
    sockets = 1
  }

  memory = var.vm_memory_mb

  os_type = "cloud-init"
  ciuser  = "ubuntu"
  sshkeys = join("\n", var.ssh_public_keys)

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
      for idx in range(var.node_count) : {
        name = "k3s-node-${format("%02d", idx + 1)}"
        ip   = cidrhost(local.node_ip_subnet, local.node_ip_start_octet + idx)
      }
    ]
  })
}
