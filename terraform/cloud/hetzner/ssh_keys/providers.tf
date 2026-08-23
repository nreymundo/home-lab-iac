terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.61"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
  required_version = ">= 1.10"

  backend "s3" {
    bucket                      = "terraform"
    key                         = "states/hetzner-ssh-keys/terraform.tfstate"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
  }
}

# Environment inputs:
# - Provider auth: HCLOUD_TOKEN

provider "hcloud" {}
