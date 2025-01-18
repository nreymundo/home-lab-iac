locals {
    # Misc
    default_name = "ubuntu-24.04"
    default_description = "Ubuntu Server Noble Image"

    # Storage
    scsi_controller = "virtio-scsi-pci"
    disk_size = "10G"
    disk_format = "raw"
    storage_pool = "ssd-zfs"
    storage_type = "virtio"

    cloud_init = true
    cloud_init_storage_pool = "ssd-zfs"

    # Network
    network_adapter_model = "virtio"
    network_adapter_bridge = "vmbr0"
    network_adapter_firewall = "false"

    # ISO
    iso_url = "https://releases.ubuntu.com/noble/ubuntu-24.04.1-live-server-amd64.iso"
    iso_checksum = "e240e4b801f7bb68c20d1356b60968ad0c33a41d00d828e74ceb3364a0317be9"
    iso_storage_pool = "unraid"
    unmount_iso = true

    # Packer settings
    boot = "c"
    boot_wait = "10s"
    communicator = "ssh"
    http_directory = "${path.root}/http"
    ssh_timeout = "30m"
    ssh_pty = true

    boot_command = [
        "<esc><wait>",
        "e<wait>",
        "<down><down><down><end>",
        "<bs><bs><bs><bs><wait>",
        "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
        "<f10><wait>"
    ]
}