output "vm_metadata" {
  description = "Metadata for the Terraform-managed Home Assistant OS VM."

  value = {
    id            = proxmox_vm_qemu.home_assistant.id
    vmid          = 251
    name          = "vm-haos"
    target_node   = "pve1"
    template_name = var.template_name
    storage       = "ssd-zfs"
    machine       = "q35"
    bios          = "ovmf"
    scsihw        = "virtio-scsi-pci"
    tags          = "terraform,home-assistant,automation"
    vm_state      = var.vm_state
  }
}

output "vmid" {
  description = "Proxmox VM ID reserved for Home Assistant OS."
  value       = 251
}

output "vm_name" {
  description = "Proxmox name of the Home Assistant OS VM."
  value       = "vm-haos"
}
