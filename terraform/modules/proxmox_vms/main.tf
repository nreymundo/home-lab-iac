data "bitwarden-secrets_secret" "ssh_public_keys" {
  id = "9b5f1231-f792-4e85-96f1-b3c60002f839"
}

locals {
  ssh_public_keys_list = compact(
    split(
      "\n",
      replace(trimspace(data.bitwarden-secrets_secret.ssh_public_keys.value), "\r\n", "\n")
    )
  )

  normalized_vms = [
    for vm in var.vms : merge(vm, {
      proxmox_tags                = distinct(concat(["terraform"], try(vm.proxmox_tags, [])))
      secondary_disk_enabled      = try(vm.secondary_disk_enabled, false)
      secondary_disk_size_gb      = try(vm.secondary_disk_size_gb, 0)
      secondary_disk_storage_pool = coalesce(try(vm.secondary_disk_storage_pool, null), vm.storage_pool)
      pci_devices                 = try(vm.pci_devices, [])
      ballooning_enabled          = coalesce(try(vm.ballooning_enabled, null), vm.vm_balloon_mb < vm.vm_memory_mb)
      effective_vm_balloon_mb     = coalesce(try(vm.ballooning_enabled, null), vm.vm_balloon_mb < vm.vm_memory_mb) ? vm.vm_balloon_mb : 0
    })
  ]
}

resource "proxmox_vm_qemu" "this" {
  count = length(local.normalized_vms)

  name        = local.normalized_vms[count.index].name
  target_node = local.normalized_vms[count.index].target_node
  vmid        = local.normalized_vms[count.index].vmid

  clone      = local.normalized_vms[count.index].template_name
  full_clone = true

  scsihw = "virtio-scsi-single"

  cpu {
    type    = "host"
    cores   = local.normalized_vms[count.index].vm_cores
    sockets = 1
  }

  memory  = local.normalized_vms[count.index].vm_memory_mb
  balloon = local.normalized_vms[count.index].effective_vm_balloon_mb

  os_type = "cloud-init"
  ciuser  = local.normalized_vms[count.index].ci_user
  sshkeys = join("\n", local.ssh_public_keys_list)

  network {
    id     = 0
    model  = "virtio"
    bridge = local.normalized_vms[count.index].network_bridge
    tag    = local.normalized_vms[count.index].vlan_id
  }

  ipconfig0  = "ip=${local.normalized_vms[count.index].ip_address}/${local.normalized_vms[count.index].ip_prefix_len},gw=${local.normalized_vms[count.index].gateway_ip}"
  nameserver = local.normalized_vms[count.index].dns_server

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = local.normalized_vms[count.index].storage_pool
          size       = local.normalized_vms[count.index].vm_disk_size_gb
          cache      = "writeback"
          iothread   = true
          discard    = true
          emulatessd = true
        }
      }

      dynamic "scsi1" {
        for_each = local.normalized_vms[count.index].secondary_disk_enabled ? [1] : []
        content {
          disk {
            storage    = local.normalized_vms[count.index].secondary_disk_storage_pool
            size       = "${local.normalized_vms[count.index].secondary_disk_size_gb}G"
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
          storage = local.normalized_vms[count.index].storage_pool
        }
      }
    }
  }

  boot               = "order=scsi0"
  start_at_node_boot = true
  agent              = 1
  tags               = join(",", local.normalized_vms[count.index].proxmox_tags)
  machine            = try(local.normalized_vms[count.index].machine, null)

  dynamic "pci" {
    for_each = { for idx, dev in local.normalized_vms[count.index].pci_devices : idx => dev }
    content {
      id         = pci.key
      mapping_id = pci.value.id
      pcie       = pci.value.pcie
      rombar     = pci.value.rombar
    }
  }

  lifecycle {
    ignore_changes = [
      cipassword,
      startup_shutdown,
    ]
  }
}
