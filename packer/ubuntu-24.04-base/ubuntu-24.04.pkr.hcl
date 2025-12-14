packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
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
  vm_id                = "9000"
  vm_name              = "ubuntu-24.04-base"
  template_description = "Ubuntu 24.04 LTS Base Image for pve1 - Built on ${timestamp()}"
  tags                 = "packer"

  # --- Common Hardware & Build Config (shared between sources) ---
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-pci"
  disks {
    disk_size    = "20G"
    format       = "raw"
    storage_pool = "ssd-zfs"
    type         = "scsi"
    discard      = true
    ssd          = true
  }
  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }
  cloud_init              = true
  cloud_init_storage_pool = "ssd-zfs"
  boot_iso {
    type     = "scsi"
    iso_file = "${var.iso_storage_pool}:iso/${var.iso_name}"
    unmount  = true
  }
  boot_wait = "10s"
  boot_command = [
    "<wait>c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot<enter>"
  ]
  ssh_username           = "ubuntu"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 100
  http_directory         = "${path.root}/${var.http_directory}"
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
  vm_id                = "9001"
  vm_name              = "ubuntu-24.04-base"
  template_description = "Ubuntu 24.04 LTS Base Image for pve2 - Built on ${timestamp()}"
  tags                 = "packer"

  # --- Common Hardware & Build Config (shared between sources) ---
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-pci"
  disks {
    disk_size    = "20G"
    format       = "raw"
    storage_pool = "ssd-zfs"
    type         = "scsi"
    discard      = true
    ssd          = true
  }
  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }
  cloud_init              = true
  cloud_init_storage_pool = "ssd-zfs"
  boot_iso {
    type     = "scsi"
    iso_file = "${var.iso_storage_pool}:iso/${var.iso_name}"
    unmount  = true
  }
  boot_wait = "10s"
  boot_command = [
    "<wait>c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot<enter>"
  ]
  ssh_username           = "ubuntu"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 100
  http_directory         = "${path.root}/${var.http_directory}"
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
