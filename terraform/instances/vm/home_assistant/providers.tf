terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07"
    }
  }
  required_version = ">= 1.10"

  backend "s3" {
    bucket                      = "terraform"
    key                         = "states/home-assistant-vm/terraform.tfstate"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
  }
}

provider "proxmox" {
  pm_tls_insecure = true
  pm_timeout      = 600
  pm_parallel     = 3
}
