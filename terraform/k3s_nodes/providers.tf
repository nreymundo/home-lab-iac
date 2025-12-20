terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc06"
    }
  }
  required_version = ">= 1.3"

  cloud {
    organization = "home-lab-iac"
    workspaces {
      name = "k3s-nodes"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_tls_insecure = true
  pm_timeout      = 600
  pm_parallel     = 3
}
