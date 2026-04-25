locals {
  ssh_keys_by_key = {
    for key, ssh_key in var.ssh_keys : key => {
      name       = coalesce(try(ssh_key.name, null), key)
      public_key = ssh_key.public_key
      labels     = merge(var.default_labels, coalesce(try(ssh_key.labels, null), {}))
    }
  }
}

resource "hcloud_ssh_key" "this" {
  for_each = local.ssh_keys_by_key

  name       = each.value.name
  public_key = each.value.public_key
  labels     = each.value.labels
}
