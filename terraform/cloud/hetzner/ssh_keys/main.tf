data "external" "ssh_public_keys" {
  program = ["${path.module}/../../../scripts/fetch-ssh-public-keys.sh"]
  query = {
    tag = "terraform"
  }
}

locals {
  ssh_public_keys_list = compact([
    for line in split(
      "\n",
      replace(trimspace(data.external.ssh_public_keys.result.keys), "\r\n", "\n")
    ) : trimspace(line)
  ])

  ssh_public_keys = [
    for public_key in local.ssh_public_keys_list : {
      public_key = public_key
      tokens     = regexall("[^\\s]+", public_key)
      key_hash   = substr(sha1(public_key), 0, 8)
      comment = trimspace(
        length(regexall("[^\\s]+", public_key)) > 2
        ? join(" ", slice(regexall("[^\\s]+", public_key), 2, length(regexall("[^\\s]+", public_key))))
        : ""
      )
    }
  ]

  ssh_key_name_by_public_key = {
    for ssh_key in local.ssh_public_keys : ssh_key.public_key => (
      ssh_key.comment != ""
      ? format("%s-%s", ssh_key.comment, ssh_key.key_hash)
      : format("ssh-key-%s", ssh_key.key_hash)
    )
  }

  ssh_keys = nonsensitive({
    for ssh_key in local.ssh_public_keys : local.ssh_key_name_by_public_key[ssh_key.public_key] => {
      name       = local.ssh_key_name_by_public_key[ssh_key.public_key]
      public_key = ssh_key.public_key
      labels     = coalesce(try(ssh_key.labels, null), {})
    }
  })
}

module "ssh_keys" {
  source = "../../../modules/hetzner/ssh_keys"

  default_labels = local.hetzner_ssh_keys.default_labels
  ssh_keys       = local.ssh_keys
}
