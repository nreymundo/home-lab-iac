# Ansible – Home Lab Configuration Management

Configuration management layer for home lab infrastructure, including Raspberry Pi edge devices, Proxmox VE nodes, and Ubuntu VM guests.

## Quick Start

```bash
# Set working directory
cd ansible/

# Install dependencies
pip install ansible ansible-lint yamllint

# Test configuration (dry run)
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check

# Apply changes
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml
```

## Directory Structure

```
ansible/
├── inventories/
│   ├── baremetal.yml              # Physical hosts (RPi + Proxmox)
│   ├── k3s-nodes.yml             # Terraform-generated VMs
│   ├── all-vms.yml               # VM group definitions
│   ├── k3s-cluster.yml           # Cluster-wide aggregation
│   ├── group_vars/               # Group-specific variables
│   │   ├── all.yml              # Shared settings
│   │   ├── rpi.yml              # RPi defaults
│   │   ├── proxmox.yml          # Proxmox overrides
│   │   └── all_vms.yml          # VM defaults
│   └── host_vars/               # Per-host overrides
├── playbooks/
│   ├── rpi.yml                  # Raspberry Pi configuration
│   ├── proxmox.yml              # Proxmox VE management
│   ├── ubuntu_vms.yml           # Ubuntu VM configuration
│   └── k3s_essentials.yml      # K3s cluster addons
├── roles/
│   ├── common/                  # Base system setup
│   ├── vm_disk_expand/          # LVM disk expansion
│   ├── k3s/                     # K3s Kubernetes setup
│   └── metallb/                 # MetalLB load balancer
└── ansible.cfg                  # Ansible configuration
```

## Playbooks

### 🍓 Raspberry Pi (`rpi.yml`)
Configures Raspberry Pi hosts running Ubuntu Server:

```bash
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml
```

**Features:**
- System hardening and security configuration
- User management with SSH key authentication
- Network configuration via Netplan
- Automated security updates
- Time synchronization

### 🖥️ Proxmox VE (`proxmox.yml`)
Manages Proxmox virtualization hosts:

```bash
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml
```

**Features:**
- Root SSH key access (prohibit-password)
- Manual upgrade control (no unattended-upgrades)
- Proxmox-specific optimizations
- Storage and network preparations

### 🐧 Ubuntu VMs (`ubuntu_vms.yml`)
Configures Ubuntu virtual machines (K3s nodes):

```bash
ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/ubuntu_vms.yml
```

**Features:**
- VM-optimized system configuration
- Automatic root filesystem expansion
- QEMU guest agent setup
- Cloud-init integration
- K3s prerequisites

### ☸️ K3s Essentials (`k3s_essentials.yml`)
Installs cluster-wide addons and essential services:

```bash
ansible-playbook -i inventories/k3s-cluster.yml playbooks/k3s_essentials.yml
```

**Features:**
- MetalLB load balancer with configurable IP address pools
- L2 advertisement for services
- Extensible role-based design for future addons

## Inventory Management

### Baremetal Hosts (`baremetal.yml`)
Physical infrastructure targets:

```yaml
all:
  children:
    rpi:
      hosts:
        main-rpi4:
          ansible_host: 192.168.1.10
    proxmox:
      hosts:
        pve1:
          ansible_host: 192.168.1.20
        pve2:
          ansible_host: 192.168.1.21
```

### Virtual Machines (`k3s-nodes.yml`)
Terraform-generated K3s cluster nodes (do not edit manually):

```yaml
all:
  children:
    k3s_nodes:
      hosts:
        k3s-node-01:
          ansible_host: 192.168.10.50
          ansible_user: ubuntu
```

### VM Groups (`all-vms.yml`)
Groups VM targets for shared configuration:

```yaml
all:
  children:
    k3s_nodes:  # Reference to k3s-nodes.yml
    baremetal_k3s:  # Physical K3s nodes
```

## Roles

### 🔧 Common Role
Provides baseline system configuration with feature toggles:

**Variable Controls:**
- `common_timezone`: System timezone setting
- `common_ntp_servers`: NTP server configuration
- `common_netplan_config`: Network configuration (optional)
- `common_ssh_keys`: SSH public keys for authentication
- `common_packages`: Additional packages to install

### 💾 VM Disk Expansion
Expands LVM-based root filesystems:

**Key Variables:**
- `vm_disk_expand_rootfs_expand`: Enable/disable expansion
- `vm_disk_expand_rootfs_device`: Root disk device
- `vm_disk_expand_rootfs_partition`: Root partition number
- `vm_disk_expand_rootfs_vg`: LVM volume group name
- `vm_disk_expand_rootfs_lv`: LVM logical volume name

### ☸️ K3s Role
Installs and configures K3s Kubernetes distribution:

**Configuration Options:**
- `k3s_version`: K3s release version
- `k3s_server_config`: Server configuration options
- `k3s_cluster_config`: Cluster-wide settings

### 🌐 MetalLB Role
Installs MetalLB load balancer for bare-metal Kubernetes clusters:

**Configuration Options:**
- `metallb_version`: MetalLB release version (default: v0.15.3)
- `metallb_namespace`: Installation namespace (default: metallb-system)
- `metallb_address_pools`: List of IP address ranges (default: ['192.168.10.200-192.168.10.240'])
- `metallb_ipaddresspool_name`: Name of the IPAddressPool (default: default)
- `metallb_l2advertisement_name`: Name of the L2Advertisement (default: default)

## Platform Behavior Matrix

| Feature | Raspberry Pi | Proxmox VE | Ubuntu VMs |
|---------|--------------|------------|------------|
| **Default User** | `pi` | `root` | `ubuntu` |
| **SSH Root Login** | Disabled | Keys Only | Disabled |
| **Auto-Upgrades** | ✅ Enabled | ❌ Disabled | ✅ Enabled |
| **Apt Dist-Upgrade** | ✅ Yes | ❌ No | ✅ Yes |
| **Hushlogin** | ✅ Created | ❌ Skipped | ✅ Created |
| **Root FS Expansion** | N/A | N/A | ✅ When enabled |

## Usage Examples

### Dry Run Mode
Test changes without applying:

```bash
# Single host
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check --limit main-rpi4

# Entire group
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check
```

### Targeted Execution
Run specific tasks on selected hosts:

```bash
# Network configuration only
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --tags netplan

# Skip package updates
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --skip-tags packages
```

### Ad-Hoc Commands
Run commands across inventory:

```bash
# Check system status
ansible -i inventories/baremetal.yml rpi -m command -a "uptime"

# Update packages
ansible -i inventories/baremetal.yml rpi -m apt -a "update_cache=yes upgrade=yes"
```

## Validation & Testing

### Syntax Checking
```bash
ansible-playbook --syntax-check -i inventories/baremetal.yml playbooks/rpi.yml
```

### Linting
```bash
ansible-lint playbooks/*.yml
yamllint .
```

### Connection Testing
```bash
ansible -i inventories/baremetal.yml all -m ping
```

## Security Considerations

- 🔒 SSH keys committed in inventory (review `group_vars/all.yml`)
- 🛡️ Root access restricted on non-management hosts
- 📦 Automated security updates on edge devices
- 🔍 Ansible vault for sensitive data (when needed)
- 🚫 No hardcoded passwords or secrets in playbooks

## Best Practices

1. **Always test with `--check`** before applying changes
2. **Use host-specific variables** for custom configurations
3. **Leverage group variables** for consistent settings
4. **Document custom configurations** in `host_vars/`
5. **Regularly update dependencies** and security patches
6. **Use tags** for granular control over task execution
