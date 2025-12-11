packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ------------------------------------------------------------------------------
# To add a new Proxmox node:
# 1. Copy one of the source blocks below
# 2. Update: node name, vm_id (increment from previous), template_description
# 3. Add the new source to the build.sources list
# Example: pve3 would use vm_id = local.vm_base_id + 2 (9002)
# ------------------------------------------------------------------------------

locals {
  # Common VM hardware configuration
  vm_cores           = 2
  vm_memory          = 2048
  vm_scsi_controller = "virtio-scsi-pci"

  # Storage configuration
  vm_disk_size       = "20G"
  vm_disk_format     = "raw"
  vm_storage_pool    = "ssd-zfs"
  vm_cloud_init_pool = "ssd-zfs"

  # Network configuration
  vm_network_bridge = "vmbr0"

  # Boot configuration
  vm_boot_wait = "10s"
  vm_boot_command = [
    "<wait>c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot<enter>"
  ]

  # SSH configuration
  vm_ssh_username           = "ubuntu"
  vm_ssh_password           = "ubuntu"
  vm_ssh_timeout            = "20m"
  vm_ssh_handshake_attempts = 100

  # Template configuration
  vm_base_id        = 9000
  vm_name           = "ubuntu-24.04-base"
  vm_tags           = "packer"
  vm_http_directory = "http"
  vm_qemu_agent     = true
  vm_task_timeout   = "20m"
}

# ------------------------------------------------------------------------------
# Source 1: Template on pve1
# ------------------------------------------------------------------------------
source "proxmox-iso" "ubuntu-base-pve1" {
  # Connection
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = "pve1"
  task_timeout             = local.vm_task_timeout

  # VM Identity
  vm_id                = local.vm_base_id
  vm_name              = local.vm_name
  template_description = "Ubuntu 24.04 LTS Base Image for pve1 - Built on ${timestamp()}"
  tags                 = local.vm_tags

  # Hardware
  cores           = local.vm_cores
  memory          = local.vm_memory
  scsi_controller = local.vm_scsi_controller

  disks {
    disk_size    = local.vm_disk_size
    format       = local.vm_disk_format
    storage_pool = local.vm_storage_pool
    type         = "scsi"
    discard      = true
    ssd          = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = local.vm_network_bridge
    firewall = false
  }

  # Cloud-init & Boot
  cloud_init              = true
  cloud_init_storage_pool = local.vm_cloud_init_pool

  boot_iso {
    type     = "scsi"
    iso_file = "${var.iso_storage_pool}:iso/${var.iso_name}"
    unmount  = true
  }

  boot_wait    = local.vm_boot_wait
  boot_command = local.vm_boot_command

  # SSH
  ssh_username           = local.vm_ssh_username
  ssh_password           = local.vm_ssh_password
  ssh_timeout            = local.vm_ssh_timeout
  ssh_handshake_attempts = local.vm_ssh_handshake_attempts

  # Misc
  http_directory = local.vm_http_directory
  qemu_agent     = local.vm_qemu_agent
}

# ------------------------------------------------------------------------------
# Source 2: Template on pve2
# ------------------------------------------------------------------------------
source "proxmox-iso" "ubuntu-base-pve2" {
  # Connection
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = "pve2"
  task_timeout             = local.vm_task_timeout

  # VM Identity
  vm_id                = local.vm_base_id + 1
  vm_name              = local.vm_name
  template_description = "Ubuntu 24.04 LTS Base Image for pve2 - Built on ${timestamp()}"
  tags                 = local.vm_tags

  # Hardware
  cores           = local.vm_cores
  memory          = local.vm_memory
  scsi_controller = local.vm_scsi_controller

  disks {
    disk_size    = local.vm_disk_size
    format       = local.vm_disk_format
    storage_pool = local.vm_storage_pool
    type         = "scsi"
    discard      = true
    ssd          = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = local.vm_network_bridge
    firewall = false
  }

  # Cloud-init & Boot
  cloud_init              = true
  cloud_init_storage_pool = local.vm_cloud_init_pool

  boot_iso {
    type     = "scsi"
    iso_file = "${var.iso_storage_pool}:iso/${var.iso_name}"
    unmount  = true
  }

  boot_wait    = local.vm_boot_wait
  boot_command = local.vm_boot_command

  # SSH
  ssh_username           = local.vm_ssh_username
  ssh_password           = local.vm_ssh_password
  ssh_timeout            = local.vm_ssh_timeout
  ssh_handshake_attempts = local.vm_ssh_handshake_attempts

  # Misc
  http_directory = local.vm_http_directory
  qemu_agent     = local.vm_qemu_agent
}


# ------------------------------------------------------------------------------
# Build Block: Defines provisioners and runs sources in parallel
# ------------------------------------------------------------------------------
build {
  sources = [
    "source.proxmox-iso.ubuntu-base-pve1",
    "source.proxmox-iso.ubuntu-base-pve2"
  ]

  provisioner "file" {
    source      = "scripts/setup.sh"
    destination = "/tmp/setup.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "echo 'ubuntu' | sudo -S /tmp/setup.sh"
    ]
  }
}
