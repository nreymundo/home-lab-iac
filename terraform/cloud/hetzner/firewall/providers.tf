terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
  required_version = ">= 1.3"

  cloud {
    organization = "home-lab-iac"
    workspaces {
      name = "hetzner-firewall"
    }
  }
}

# Environment inputs:
# - Provider auth: HCLOUD_TOKEN

provider "hcloud" {}
