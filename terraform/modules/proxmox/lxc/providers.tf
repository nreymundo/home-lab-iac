terraform {
  required_version = ">= 1.4"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.106"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
