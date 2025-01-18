source "proxmox-iso" "ubuntu" {
    # Proxmox Settings
    proxmox_url = "${var.proxmox_api_url}"
    username = "${var.proxmox_api_token_id}"
    token = "${var.proxmox_api_token_secret}"
    insecure_skip_tls_verify = var.proxmox_skip_tls_verify
    tags = "packer"
    
    # VM Settings
    vm_id = "8000"
    qemu_agent = true
    cores = var.cores
    memory = var.memory
    node = var.proxmox_node
    vm_name = local.default_name
    template_description = local.default_description
    
    # Storage Settings
    scsi_controller = local.scsi_controller
    disks {
        disk_size = local.disk_size
        format = local.disk_format
        storage_pool = local.storage_pool
        type = local.storage_type
    }
    # Cloud Init Settings
    cloud_init = local.cloud_init
    cloud_init_storage_pool = local.cloud_init_storage_pool
    
    # Network Settings
    network_adapters {
        model = local.network_adapter_model
        bridge = local.network_adapter_bridge
        firewall = local.network_adapter_firewall
    }

    # Packer settings to connect to the VM
    boot                    = local.boot
    boot_wait               = local.boot_wait
    communicator            = local.communicator
    http_directory          = local.http_directory
    http_bind_address       = "${var.local_http_address}"
    ssh_username            = "${var.ssh_username}"
    ssh_private_key_file    = "${var.ssh_private_key_file}"
    ssh_timeout             = local.ssh_timeout
    ssh_pty                 = local.ssh_pty

    # VM OS Settings
    boot_iso {
        iso_url = local.iso_url
        iso_checksum = local.iso_checksum
        iso_storage_pool = local.iso_storage_pool
        unmount = local.unmount_iso
        keep_cdrom_device = local.unmount_iso
    }

    boot_command = local.boot_command
}