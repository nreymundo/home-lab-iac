# Home Assistant OS VM

This root creates VM 251 by full-cloning a manually prepared Home Assistant OS
(HAOS) template. It deliberately does not use the shared cloud-init VM module:
HAOS is an appliance and does not consume Proxmox cloud-init or `ipconfig0`.

Terraform manages the VM configuration only. It does not download, import, or
reflash HAOS during a normal plan or apply.

## Bootstrap the HAOS template

From a trusted workstation with SSH access to `pve1`, choose an unused template
VMID and inspect the operation first. `9001` below is only an example.

```bash
terraform/instances/vm/home_assistant/scripts/build-haos-template.sh \
  --template-vmid 9001 \
  --dry-run

terraform/instances/vm/home_assistant/scripts/build-haos-template.sh \
  --template-vmid 9001
```

The script downloads the pinned official HAOS 18.2 KVM QCOW2, validates its
locally recorded SHA-256 and XZ container, writes the supported
`CONFIG/network/20-home-assistant` NetworkManager profile to the image boot
partition, imports it as a raw ZFS volume, and converts the stopped result into
the `haos-18.2` template. It never starts the template and never runs external
code fetched from the network.

The HAOS release has no official checksum or signature asset. The digest in the
script was recorded from an HTTPS download of the pinned official release URL.
It is a reproducibility pin, not upstream signature verification. Review and
change the URL and digest together for a future release.

Inspect an existing template without downloading or mutating anything:

```bash
terraform/instances/vm/home_assistant/scripts/build-haos-template.sh \
  --template-vmid 9001 \
  --verify
```

## Create and start VM 251

The Terraform default is `vm_state = "stopped"`. This permits creation of VM
251 without conflicting with the legacy VM 102, which currently owns the static
`192.168.20.10` address.

```bash
ROOT=terraform/instances/vm/home_assistant
terraform -chdir="$ROOT" init
terraform -chdir="$ROOT" plan
terraform -chdir="$ROOT" apply
```

Readdress and validate VM 102 outside this Terraform root. Then start VM 251
intentionally:

```bash
terraform -chdir="$ROOT" apply -var='vm_state=running'
```

VM 251 has one provider-assigned-MAC VirtIO NIC on `vmbr0`, VLAN 20. HAOS is
configured by its supported CONFIG import mechanism with static
`192.168.20.10/24`, gateway `192.168.20.1`, and DNS `192.168.10.2`. No DHCP
reservation or Ansible inventory is involved.

## Image lifecycle

HAOS updates itself through Supervisor. Routine Terraform applies change only
the existing VM configuration and never invoke the bootstrap script. The VM
uses `prevent_destroy` and ignores clone-source changes, so a template update
cannot silently replace the appliance disk.

For a later HAOS base image, manually build a new versioned template. Use it
only for a reviewed rebuild or a separate migration VM; never change the clone
source of the live VM merely because a newer HAOS release exists.
