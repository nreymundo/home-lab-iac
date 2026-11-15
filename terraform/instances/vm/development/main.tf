resource "libvirt_domain" "development" {
  name        = local.vm_definition.name
  type        = "kvm"
  gen_id      = local.vm_definition.generation_id
  description = "Managed by Terraform."
  memory      = local.vm_definition.memory_kib
  memory_unit = "KiB"
  vcpu        = local.vm_definition.cores
  io_threads  = 1
  running     = true
  autostart   = false
  update      = { shutdown = { timeout = 120 } }

  metadata = {
    xml = "<vmtemplate xmlns=\"http://unraid\" name=\"Ubuntu\" icon=\"ubuntu.png\" os=\"ubuntu\"/>\n"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "pc-q35-10.2"
    boot_devices = [{ dev = "hd" }]
    sm_bios      = { mode = "sysinfo" }
  }

  sys_info = [{
    smbios = {
      system = {
        entry = [{ name = "uuid", value = local.vm_definition.smbios_uuid }]
      }
    }
  }]

  features = {
    acpi = true
    apic = {}
  }

  cpu = {
    mode     = "host-passthrough"
    check    = "none"
    topology = { sockets = 1, dies = 1, clusters = 1, cores = local.vm_definition.cores, threads = 1 }
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
    disks = [
      {
        device = "disk"
        driver = {
          name    = "qemu"
          type    = "qcow2"
          cache   = "none"
          io      = "io_uring"
          discard = "unmap"
        }
        source = { file = { file = "${local.vm_definition.disk_directory}/vdisk1.qcow2" } }
        target = { dev = "sda", bus = "scsi" }
      },
      {
        device    = "cdrom"
        driver    = { name = "qemu", type = "raw" }
        source    = { file = { file = "${local.vm_definition.disk_directory}/cloudinit.iso" } }
        target    = { dev = "sdb", bus = "sata" }
        read_only = true
      }
    ]
    interfaces = [{
      mac    = { address = "bc:24:11:16:c2:fc" }
      source = { bridge = { bridge = "br0" } }
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
}
