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
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "0.5.4-pre"
    }
  }
  required_version = ">= 1.10"

  backend "s3" {
    bucket                      = "terraform"
    key                         = "states/photon-lxc/terraform.tfstate"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
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

# Environment inputs:
# - Provider auth/endpoint: BW_ORGANIZATION_ID, BW_ACCESS_TOKEN

provider "bitwarden-secrets" {
  api_url      = "https://api.bitwarden.com"
  identity_url = "https://identity.bitwarden.com"
}
