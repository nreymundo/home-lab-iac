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
      },
      http = {
        name = "http"
        labels = {
          role = "ingress"
        }
        rules = [
          {
            direction   = "in"
            protocol    = "tcp"
            port        = "80"
            source_ips  = ["0.0.0.0/0", "::/0"]
            description = "Allow HTTP"
          },
        ]
      },
      https = {
        name = "https"
        labels = {
          role = "ingress"
        }
        rules = [
          {
            direction   = "in"
            protocol    = "tcp"
            port        = "443"
            source_ips  = ["0.0.0.0/0", "::/0"]
            description = "Allow HTTPS"
          },
        ]
      },
      netbird-udp = {
        name = "netbird-udp"
        labels = {
          role = "netbird"
        }
        rules = [
          {
            direction   = "in"
            protocol    = "udp"
            port        = "3478"
            source_ips  = ["0.0.0.0/0", "::/0"]
            description = "Allow UDP port for Netbird"
          },
        ]
      },
      wireguard = {
        name = "wireguard"
        labels = {
          role = "vpn"
        }
        rules = [
          {
            direction   = "in"
            protocol    = "udp"
            port        = "51820"
            source_ips  = ["0.0.0.0/0", "::/0"]
            description = "Allow WireGuard VPN"
          },
        ]
      }
    }
  }
}
