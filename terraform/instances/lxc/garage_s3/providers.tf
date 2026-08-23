terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.106"
    }
  }
  required_version = ">= 1.4"

  cloud {
    organization = "home-lab-iac"
    workspaces {
      name = "garage-s3-lxc"
    }
  }
}

# Environment inputs:
# - Provider auth/endpoint: PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN
# - Local compatibility mapping:
#   export PROXMOX_VE_ENDPOINT="$PM_API_URL"
#   export PROXMOX_VE_API_TOKEN="$PM_API_TOKEN_ID=$PM_API_TOKEN_SECRET"

provider "proxmox" {
  insecure = true
}
