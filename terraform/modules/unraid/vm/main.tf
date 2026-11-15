locals {
  vms_by_name = { for vm in var.vms : vm.name => vm }
}

resource "macaddress" "nic" {
  for_each = local.vms_by_name
}

resource "random_uuid" "generation" {
  for_each = local.vms_by_name
}

resource "libvirt_domain" "this" {
  for_each = local.vms_by_name

  name        = each.value.name
  type        = "kvm"
  gen_id      = random_uuid.generation[each.key].result
  description = "Managed by Terraform."
  memory      = each.value.vm_memory_mb * 1024
  memory_unit = "KiB"
  vcpu        = each.value.vm_cores
  io_threads  = 1
  running     = each.value.running
  autostart   = each.value.start_at_node_boot
  update      = { shutdown = { timeout = each.value.shutdown_timeout } }

  metadata = {
    xml = "<vmtemplate xmlns=\"http://unraid\" name=\"${title(each.value.os_type)}\" icon=\"${each.value.os_type}.png\" os=\"${each.value.os_type}\"/>\n"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = each.value.machine
    boot_devices = [{ dev = "hd" }]
  }


  features = {
    acpi = true
    apic = {}
  }

  cpu = {
    mode     = "host-passthrough"
    check    = "none"
    topology = { sockets = 1, dies = 1, clusters = 1, cores = each.value.vm_cores, threads = 1 }
  }

  clock       = { offset = "utc" }
  on_poweroff = "destroy"
  on_reboot   = "restart"
  on_crash    = "restart"

  devices = {
    emulator = "/usr/bin/qemu-system-x86_64"
    controllers = [{
      type   = "scsi"
      index  = 0
      model  = "virtio-scsi"
      driver = { io_thread = 1 }
    }]
    disks = concat([
      {
        device = "disk"
        driver = {
          name    = "qemu"
          type    = each.value.disk_format
          cache   = "none"
          io      = "io_uring"
          discard = "unmap"
        }
        source = { file = { file = each.value.disk_path } }
        target = { dev = "sda", bus = "scsi" }
      }
      ], each.value.cloudinit_path == null ? [] : [
      {
        device    = "cdrom"
        driver    = { name = "qemu", type = "raw" }
        source    = { file = { file = each.value.cloudinit_path } }
        target    = { dev = "sdb", bus = "sata" }
        read_only = true
      }
    ])
    interfaces = [{
      mac    = { address = lower(macaddress.nic[each.key].address) }
      source = { bridge = { bridge = each.value.network_bridge } }
      model  = { type = "virtio" }
    }]
    channels = [{
      source = { unix = { mode = "bind" } }
      target = { virt_io = { name = "org.qemu.guest_agent.0" } }
    }]
    graphics = [{
      vnc = {
        auto_port = true
        listen    = "127.0.0.1"
        listeners = [{ address = { address = "127.0.0.1" } }]
      }
    }]
    videos = [{
      model = { type = "vga", vram = 16384, heads = 1, primary = "yes" }
    }]
    mem_balloon = { model = "virtio" }
  }

  lifecycle {
    ignore_changes = [sys_info, os.sm_bios]
  }
}
