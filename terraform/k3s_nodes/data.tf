data "bitwarden-secrets_secret" "ssh_public_keys" {
  id = var.ssh_keys_secret_id
}
