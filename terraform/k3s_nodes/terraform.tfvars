nodes = [
  {
    template_name = "ubuntu-24.04-base"
    ci_user       = "ubuntu"
    target_node   = "pve1"
    machine       = "q35"
    pci_devices = [
      {
        # Requires manual creation of 'intel-iris-xe' PCI Resource Mapping in Proxmox Datacenter
        id = "intel-iris-xe"
      }
    ]
  },
  {
    template_name = "ubuntu-24.04-base"
    ci_user       = "ubuntu"
    target_node   = "pve2"
  }
]
