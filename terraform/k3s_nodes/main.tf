locals {
  node_ip_subnet      = "${join(".", slice(split(".", var.node_ip_start), 0, 3))}.0/${var.ip_prefix_len}"
  node_ip_start_octet = tonumber(split(".", var.node_ip_start)[3])
  node_count          = length(var.nodes)
  node_ci_users = [
    for node_index, node in var.nodes : coalesce(try(node.ci_user, null), var.default_ci_user)
  ]
  node_ansible_users = [
    for node_index, node in var.nodes : coalesce(try(node.ansible_user, null), local.node_ci_users[node_index])
  ]
  node_resource_defaults = {
    vm_cores               = var.vm_cores
    vm_memory_mb           = var.vm_memory_mb
    vm_balloon_mb          = var.vm_balloon_mb
    vm_disk_size_gb        = var.vm_disk_size_gb
    secondary_disk_size_gb = var.secondary_disk_size_gb
  }
  _node_resource_overrides = {
    for attr, default_value in local.node_resource_defaults :
    attr => [for node in var.nodes : coalesce(try(node[attr], null), default_value)]
  }
  node_cores                  = local._node_resource_overrides.vm_cores
  node_memory_mb              = local._node_resource_overrides.vm_memory_mb
  node_balloon_mb             = local._node_resource_overrides.vm_balloon_mb
  node_disk_size_gb           = local._node_resource_overrides.vm_disk_size_gb
  node_secondary_disk_size_gb = local._node_resource_overrides.secondary_disk_size_gb
  node_target_nodes = [
    for node_index, node in var.nodes : coalesce(try(node.target_node, null), element(var.proxmox_nodes, node_index % length(var.proxmox_nodes)))
  ]
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
  target_node = local.node_target_nodes[count.index]
  vmid        = var.node_vmid_start + count.index

  clone      = coalesce(try(var.nodes[count.index].template_name, null), var.template_name)
  full_clone = true

  scsihw = "virtio-scsi-single"

  cpu {
    type    = "host"
    cores   = local.node_cores[count.index]
    sockets = 1
  }

  memory  = local.node_memory_mb[count.index]
  balloon = local.node_balloon_mb[count.index]

  os_type = "cloud-init"
  ciuser  = local.node_ci_users[count.index]
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
          size       = local.node_disk_size_gb[count.index]
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
            size       = "${local.node_secondary_disk_size_gb[count.index]}G"
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

  boot   = "order=scsi0"
  onboot = true
  agent  = 1
  tags   = "terraform,k3s-node"

  machine = try(var.nodes[count.index].machine, null)

  # PCI Passthrough
  dynamic "pci" {
    for_each = { for idx, dev in try(var.nodes[count.index].pci_devices, []) : idx => dev }
    content {
      id         = pci.key # Use index as PCI ID
      mapping_id = pci.value.id
      pcie       = pci.value.pcie
      rombar     = pci.value.rombar
    }
  }

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
      for node_index in range(local.node_count) : {
        name         = "k3s-node-${format("%02d", node_index + 1)}"
        ip           = cidrhost(local.node_ip_subnet, local.node_ip_start_octet + node_index)
        ansible_user = local.node_ansible_users[node_index]
        node_os      = local.node_ci_users[node_index]
        labels = merge(
          {
            "homelab.lan/role"            = "general"
            "homelab.lan/cpu-vendor"      = "intel"
            "homelab.lan/runtime"         = "vm"
            "homelab.lan/hypervisor"      = "proxmox"
            "homelab.lan/gpu"             = length(try(var.nodes[node_index].pci_devices, [])) > 0 ? "intel" : "none"
            "topology.kubernetes.io/zone" = local.node_target_nodes[node_index]
          },
          try(var.nodes[node_index].labels, {})
        )
      }
    ]
  })
}
