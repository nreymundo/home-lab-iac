terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
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
      name = "hetzner-servers"
    }
  }
}

# Environment inputs:
# - Provider auth: HCLOUD_TOKEN

provider "hcloud" {}

# Environment inputs:
# - Provider auth/endpoint: BW_ORGANIZATION_ID, BW_ACCESS_TOKEN

provider "bitwarden-secrets" {
  api_url      = "https://api.bitwarden.com"
  identity_url = "https://identity.bitwarden.com"
}
