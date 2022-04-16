terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.7"
    }
  }
}

provider "proxmox" {
    pm_api_url = "${var.proxmox_host}/api2/json"
    pm_tls_insecure = "false"
}