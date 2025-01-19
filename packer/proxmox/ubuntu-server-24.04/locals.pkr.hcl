locals {
  # Misc
  default_name        = "ubuntu-24.04"
  default_description = "Ubuntu Server Noble Image"

  # Storage
  scsi_controller = "virtio-scsi-pci"
  disk_size       = "10G"
  disk_format     = "raw"
  storage_pool    = "ssd-zfs"
  storage_type    = "virtio"

  cloud_init              = true
  cloud_init_storage_pool = "ssd-zfs"

  # Network
  network_adapter_model    = "virtio"
  network_adapter_bridge   = "vmbr0"
  network_adapter_firewall = "false"

  # ISO
  iso_url          = "https://releases.ubuntu.com/noble/ubuntu-24.04.1-live-server-amd64.iso"
  iso_checksum     = "e240e4b801f7bb68c20d1356b60968ad0c33a41d00d828e74ceb3364a0317be9"
  iso_storage_pool = "unraid"
  unmount_iso      = true

  # Packer settings
  boot           = "c"
  boot_wait      = "10s"
  communicator   = "ssh"
  http_directory = "${path.root}/http"
  ssh_timeout    = "30m"
  ssh_pty        = true

  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]

  # Provisioning
  ansible_use_proxy     = false
  ansible_playbook_base = "${path.root}/../../../ansible/playbooks/ubuntu/base-provisioning.yml"

  cloud_init_cleanup = [
    "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
    "sudo rm /etc/ssh/ssh_host_*",
    "sudo truncate -s 0 /etc/machine-id",
    "sudo apt -y autoremove --purge",
    "sudo apt -y clean",
    "sudo apt -y autoclean",
    "sudo cloud-init clean",
    "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
    "sudo rm -f /etc/netplan/00-installer-config.yaml",
    "sudo sync"
  ]
  cloud_init_cleanup_file  = "${path.root}/files/99-pve.cfg"
  cloud_init_cleanup_shell = ["sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"]
}