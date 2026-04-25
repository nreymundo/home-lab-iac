module "firewall" {
  source = "../../../modules/hetzner/firewall"

  default_labels = local.hetzner_firewall.default_labels
  firewalls      = local.hetzner_firewall.firewalls
}
