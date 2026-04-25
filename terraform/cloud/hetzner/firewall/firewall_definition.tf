locals {
  admin_cidrs = ["0.0.0.0/0", "::/0"] # Yes yes, I know this is the entire wide internet. The jows of non-static IPs. I'll figure it out later.

  hetzner_firewall = {
    default_labels = {
      managed_by = "terraform"
    }
    firewalls = {
      ssh = {
        name = "ssh"
        labels = {
          role = "admin"
        }
        rules = [
          {
            direction   = "in"
            protocol    = "tcp"
            port        = "2222"
            source_ips  = local.admin_cidrs
            description = "Allow SSH from trusted admin networks"
          },
        ]
      }
    }
  }
}
