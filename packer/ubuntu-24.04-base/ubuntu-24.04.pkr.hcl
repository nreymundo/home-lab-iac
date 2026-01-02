packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

locals {
  vm_name              = "ubuntu-24.04-base"
  template_desc_prefix = "Ubuntu 24.04 LTS Base Image for"
  template_desc_suffix = "- Built on ${timestamp()}"
  cores                = 2
  memory               = 2048
  scsi_controller      = "virtio-scsi-pci"
  disk_size            = "20G"
  disk_format          = "raw"
  disk_storage_pool    = "ssd-zfs"
  disk_type            = "scsi"
  disk_discard         = true
  disk_ssd             = true
  network_model        = "virtio"
  network_bridge       = "vmbr0"
  network_firewall     = false
  cloud_init_storage   = "ssd-zfs"
  boot_wait            = "10s"
  boot_command = [
    "<wait>c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot<enter>"
  ]
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 100
  http_directory         = "${path.root}/${var.http_directory}"

  # VM ID calculation: Ubuntu base (9000) + node number
  distro_base_id = 9000
  pve1_vm_id     = 9001 # 9000 + 1
  pve2_vm_id     = 9002 # 9000 + 2
}

# ------------------------------------------------------------------------------
# Source 1: Template on pve1
# ------------------------------------------------------------------------------
source "proxmox-iso" "ubuntu-base-pve1" {
  # --- Connection Details ---
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = "pve1"
  task_timeout             = "20m"

  # --- VM Configuration ---
  vm_id                = local.pve1_vm_id
  vm_name              = local.vm_name
  template_description = "${local.template_desc_prefix} pve1 ${local.template_desc_suffix}"
  tags                 = "packer;pve1"

  # --- Common Hardware & Build Config (shared between sources) ---
  cores           = local.cores
  memory          = local.memory
  scsi_controller = local.scsi_controller
  disks {
    disk_size    = local.disk_size
    format       = local.disk_format
    storage_pool = local.disk_storage_pool
    type         = local.disk_type
    discard      = local.disk_discard
    ssd          = local.disk_ssd
  }
  network_adapters {
    model    = local.network_model
    bridge   = local.network_bridge
    firewall = local.network_firewall
  }
  cloud_init              = true
  cloud_init_storage_pool = local.cloud_init_storage
  boot_iso {
    type     = "scsi"
    iso_file = "${var.iso_storage_pool}:iso/${var.iso_name}"
    unmount  = true
  }
  boot_wait              = local.boot_wait
  boot_command           = local.boot_command
  ssh_username           = "ubuntu"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = local.ssh_timeout
  ssh_handshake_attempts = local.ssh_handshake_attempts
  http_directory         = local.http_directory
  qemu_agent             = true
}

# ------------------------------------------------------------------------------
# Source 2: Template on pve2
# ------------------------------------------------------------------------------
source "proxmox-iso" "ubuntu-base-pve2" {
  # --- Connection Details ---
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = "pve2"
  task_timeout             = "20m"

  # --- VM Configuration ---
  vm_id                = local.pve2_vm_id
  vm_name              = local.vm_name
  template_description = "${local.template_desc_prefix} pve2 ${local.template_desc_suffix}"
  tags                 = "packer;pve2"

  # --- Common Hardware & Build Config (shared between sources) ---
  cores           = local.cores
  memory          = local.memory
  scsi_controller = local.scsi_controller
  disks {
    disk_size    = local.disk_size
    format       = local.disk_format
    storage_pool = local.disk_storage_pool
    type         = local.disk_type
    discard      = local.disk_discard
    ssd          = local.disk_ssd
  }
  network_adapters {
    model    = local.network_model
    bridge   = local.network_bridge
    firewall = local.network_firewall
  }
  cloud_init              = true
  cloud_init_storage_pool = local.cloud_init_storage
  boot_iso {
    type     = "scsi"
    iso_file = "${var.iso_storage_pool}:iso/${var.iso_name}"
    unmount  = true
  }
  boot_wait              = local.boot_wait
  boot_command           = local.boot_command
  ssh_username           = "ubuntu"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = local.ssh_timeout
  ssh_handshake_attempts = local.ssh_handshake_attempts
  http_directory         = local.http_directory
  qemu_agent             = true
}


# ------------------------------------------------------------------------------
# Build Block: Defines provisioners and runs sources in parallel
# ------------------------------------------------------------------------------
build {
  sources = [
    "source.proxmox-iso.ubuntu-base-pve1",
    "source.proxmox-iso.ubuntu-base-pve2"
  ]

  # NOTE: user-data is generated by build.sh before packer runs
  # Run: ./build.sh instead of packer build .

  provisioner "file" {
    source      = "${path.root}/scripts/setup.sh"
    destination = "/tmp/setup.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E sh -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "chmod +x /tmp/setup.sh",
      "/tmp/setup.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "sudo -E sh -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "rm -rf /root/.ssh || true"
    ]
  }
}
