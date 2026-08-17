resource "proxmox_vm_qemu" "home_assistant" {
  name        = "vm-haos"
  target_node = "pve1"
  vmid        = 251

  clone      = var.template_name
  full_clone = true

  machine = "q35"
  bios    = "ovmf"

  scsihw = "virtio-scsi-pci"

  # Match the full-cloned HAOS root disk. Lifecycle ignores below keep future
  # provider refreshes from replacing or deleting this inherited boot disk.
  disk {
    type       = "disk"
    slot       = "scsi0"
    storage    = "ssd-zfs"
    size       = "100G"
    format     = "raw"
    asyncio    = "io_uring"
    cache      = "none"
    discard    = true
    emulatessd = true
  }

  cpu {
    type    = "kvm64"
    cores   = 2
    sockets = 1
  }

  memory  = 6144
  balloon = 3072

  agent              = 1
  tablet             = false
  start_at_node_boot = true
  boot               = "order=scsi0"
  vm_state           = var.vm_state
  skip_ipv6          = true

  serial {
    id   = 0
    type = "socket"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
    tag    = 20
  }

  # HAOS owns the cloned scsi0 disk. Do not declare a disks block here.
  # HAOS also does not consume Terraform's ipconfig0 convention.
  tags = "terraform,home-assistant,automation"

  lifecycle {
    # The template's disks are immutable bootstrap inputs. A release update
    # must never reflash, replace, or delete the existing boot disks.
    ignore_changes = [clone, disk, efidisk, startup_shutdown]
  }
}
