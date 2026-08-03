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

  # Bootstrap dependency: this root manages the Garage LXC that hosts this backend.
  # For first creation, use a temporary local backend; migrate state here only after
  # Garage and the `terraform` bucket are healthy. Never apply from empty recovery state.
  backend "s3" {
    bucket = "terraform"
    key    = "states/garage-s3-lxc/terraform.tfstate"

    use_path_style = true
    use_lockfile   = true

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}

# Environment inputs:
# - Provider auth/endpoint: PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN
# - Local compatibility mapping:
#   export PROXMOX_VE_ENDPOINT="$PM_API_URL"
#   export PROXMOX_VE_API_TOKEN="$PM_API_TOKEN_ID=$PM_API_TOKEN_SECRET"
# - Backend (S3/Garage), env-sourced: AWS_ENDPOINT_URL_S3, AWS_REGION,
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

provider "proxmox" {
  insecure = true
}

# Environment inputs:
# - Provider auth/endpoint: BW_ORGANIZATION_ID, BW_ACCESS_TOKEN

provider "bitwarden-secrets" {
  api_url      = "https://api.bitwarden.com"
  identity_url = "https://identity.bitwarden.com"
}
