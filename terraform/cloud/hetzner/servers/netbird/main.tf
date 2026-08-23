data "external" "ssh_public_keys" {
  program = ["${path.module}/../../../../scripts/fetch-ssh-public-keys.sh"]
  query = {
    tag = "terraform"
  }
}

data "terraform_remote_state" "firewall" {
  backend = "s3"

  config = {
    bucket = "terraform"
    key    = "states/hetzner-firewall/terraform.tfstate"

    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
  }
}

module "vm" {
  source = "../../../../modules/hetzner/vm"

  default_labels     = local.default_labels
  default_cloud_init = local.default_cloud_init
  vms                = [local.vm]
}
