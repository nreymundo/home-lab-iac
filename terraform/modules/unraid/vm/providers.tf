terraform {
  required_version = ">= 1.3"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.6"
    }
    macaddress = {
      source  = "ivoronin/macaddress"
      version = "~> 0.3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
