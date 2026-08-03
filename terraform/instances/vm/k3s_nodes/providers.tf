terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07"
    }
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "0.5.4-pre"
    }
  }
  required_version = ">= 1.10"

  backend "s3" {
    bucket = "terraform"
    key    = "states/k3s-nodes/terraform.tfstate"

    use_path_style = true
    use_lockfile   = true

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}

# Environment inputs:
# - Provider auth/endpoint: PM_API_URL, PM_API_TOKEN_ID, PM_API_TOKEN_SECRET
# - Backend (S3/Garage), env-sourced: AWS_ENDPOINT_URL_S3, AWS_REGION,
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

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
