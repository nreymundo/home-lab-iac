variable "proxmox_host" {
    type    = string
    default = ""
}

variable "proxmox_node" {
    type    = string
    default = "pve1"
}

variable "vm_name" {
    type    = string
    default = ""
}

variable "vm_start_boot" {
    type    = bool
    default = true
}

variable "vm_cpu_type" {
    type    = string
    default = "kvm64"
}

variable "vm_cores" {
    type    = number
    default = 1
}

variable "vm_min_memory" {
    type    = number
    default = 1024
}

variable "vm_max_memory" {
    type    = number
    default = 2048
}

variable "vm_template" {
    type    = string
    default = "ubuntu2004-cloud"
}

variable "vm_disk_size" {
    type    = string
    default = "10G" 
}

variable "vm_disk_storage" {
    type    = string
    default = "ssd-zfs"
}

variable "vm_disk_iothread" {
    type    = number
    default = 0
}

variable "ansible_playbook" {
    type    = string
    default = ""
}