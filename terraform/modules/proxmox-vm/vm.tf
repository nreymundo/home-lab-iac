resource "proxmox_vm_qemu" "vm" {
  name = var.vm_name
  target_node = var.proxmox_node
  clone = var.vm_template
  onboot = var.vm_start_boot
  agent = 1
  os_type = "cloud-init"
  cores = var.vm_cores
  sockets = 1
  cpu = var.vm_cpu_type
  balloon = var.vm_min_memory
  memory = var.vm_max_memory
  scsihw = "virtio-scsi-pci"
  bootdisk = "scsi0"
  disk {
    slot = 0
    size = var.vm_disk_size
    type = "scsi"
    storage = var.vm_disk_storage
    iothread = var.vm_disk_iothread
  }
  
  network {
    model = "virtio"
    bridge = "vmbr0"
  }

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${self.default_ipv4_address},' ${var.ansible_playbook}"
  }

}