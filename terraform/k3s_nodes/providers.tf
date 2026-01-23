terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07"
    }
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "0.5.4-pre"
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

# Environment inputs:
# - Provider auth/endpoint: BW_ORGANIZATION_ID, BW_ACCESS_TOKEN

provider "bitwarden-secrets" {
  api_url      = "https://api.bitwarden.com"
  identity_url = "https://identity.bitwarden.com"
}
