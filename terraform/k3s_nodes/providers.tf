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

# Environment inputs:
# - Provider auth/endpoint: PM_API_URL, PM_API_TOKEN_ID, PM_API_TOKEN_SECRET

provider "proxmox" {
  pm_tls_insecure = true
  pm_timeout      = 600
  pm_parallel     = 3
}
