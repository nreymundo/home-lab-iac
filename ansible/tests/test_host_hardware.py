"""Offline behavioral checks for the host_hardware Ansible role."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml
from ansible.parsing.dataloader import DataLoader
from ansible.plugins.loader import init_plugin_loader
from ansible.playbook.block import Block
from ansible.playbook.play import Play
from ansible.playbook.task import Task


ANSIBLE_ROOT = Path(__file__).resolve().parents[1]
ROLE_ROOT = ANSIBLE_ROOT / "roles/host_hardware"


class HostHardwareRoleTests(unittest.TestCase):
    def make_pci_device(self, root, bdf, vendor, device, pci_class="0x030000", driver=None):
        path = root / bdf
        path.mkdir(parents=True)
        (path / "vendor").write_text(vendor)
        (path / "device").write_text(device)
        (path / "class").write_text(pci_class)
        if driver:
            driver_path = root / "drivers" / driver
            driver_path.mkdir(parents=True, exist_ok=True)
            (path / "driver").symlink_to(driver_path)

    def run_role_facts(self, release, cpu, devices, profiles=None, virtualization_role="host", physical=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sysfs = root / "pci"
            sysfs.mkdir()
            for device in devices:
                self.make_pci_device(sysfs, *device)

            preflight = yaml.safe_load((ROLE_ROOT / "tasks/preflight.yml").read_text())
            package_tasks = yaml.safe_load((ROLE_ROOT / "tasks/packages.yml").read_text())
            gpu_package_tasks = yaml.safe_load((ROLE_ROOT / "tasks/gpu-packages.yml").read_text())
            # Execute the role's real discovery/fact and release/package selection
            # tasks. Omit tasks which install packages/services on the controller.
            selected_preflight = preflight[:5]
            selected_package_tasks = [package_tasks[0], package_tasks[1], gpu_package_tasks[0]]
            tasks = selected_preflight + selected_package_tasks + [
                {"ansible.builtin.debug": {"var": item}}
                for item in (
                    "host_hardware_gpu_devices",
                    "host_hardware_selected_gpu_profiles",
                    "host_hardware_cpu_vendor",
                    "host_hardware_packages",
                    "host_hardware_gpu_packages",
                )
            ]
            playbook = root / "test.yml"
            playbook.write_text(yaml.safe_dump([{
                "hosts": "localhost",
                "gather_facts": False,
                "connection": "local",
                "vars_files": [str(ROLE_ROOT / "vars/main.yml")],
                "vars": {
                    "ansible_distribution": "Ubuntu",
                    "ansible_distribution_release": release,
                    "ansible_processor": [cpu],
                    "ansible_virtualization_role": virtualization_role,
                    "host_hardware_physical": physical,
                    "host_hardware_gpu_profiles": ["auto"] if profiles is None else profiles,
                    "host_hardware_gpu_sysfs_root": str(sysfs),
                    "host_hardware_install_diagnostics": False,
                    "host_hardware_extra_packages": ["caller-package", "linux-firmware"],
                },
                "tasks": tasks,
            }], sort_keys=False))
            inventory = root / "inventory.yml"
            inventory.write_text("all:\n  hosts:\n    localhost:\n      ansible_connection: local\n")
            result = subprocess.run(
                ["ansible-playbook", "-i", str(inventory), str(playbook)],
                check=False,
                capture_output=True,
                text=True,
                env={**os.environ, "ANSIBLE_CONFIG": str(ANSIBLE_ROOT / "ansible.cfg")},
            )
            self.assertEqual(result.returncode, 0, f"Fixture play failed:\n{result.stdout}\n{result.stderr}")
            return result.stdout

    def test_auto_detects_multiple_gpu_vendors_independently_of_amd_cpu(self):
        output = self.run_role_facts("noble", "AuthenticAMD", [
            ("0000:01:00.0", "0x1002", "0x1234", "0x030000", "amdgpu"),
            ("0000:02:00.0", "0x8086", "0x5678", "0x030200", "i915"),
            ("0000:00:14.0", "0x8086", "0x1111", "0x0c0330", None),
        ])
        self.assertIn('"vendor_id": "0x1002"', output)
        self.assertIn('"vendor_id": "0x8086"', output)
        self.assertIn('"host_hardware_selected_gpu_profiles": [\n        "intel",\n        "amd"', output)
        self.assertIn('"host_hardware_cpu_vendor": "amd"', output)
        self.assertIn('"mesa-va-drivers"', output)
        self.assertIn('"intel-media-va-driver-non-free"', output)
        self.assertIn('"amd64-microcode"', output)
        self.assertIn('"caller-package"', output)
        self.assertEqual(output.count("linux-firmware"), 1)

    def test_no_gpu_kvm_guest_does_not_infer_amd_from_cpu(self):
        output = self.run_role_facts("resolute", "AuthenticAMD", [], virtualization_role="guest", physical=False)
        self.assertIn('"host_hardware_gpu_devices": []', output)
        self.assertIn('"host_hardware_selected_gpu_profiles": []', output)
        self.assertIn('"host_hardware_cpu_vendor": "amd"', output)
        self.assertNotIn('"amd64-microcode"', output)
        self.assertNotIn("mesa-libgallium", output)
        self.assertNotIn("intel-media-va-driver-non-free", output)

    def test_resolute_amd_gpu_uses_release_specific_vaapi_package(self):
        output = self.run_role_facts("resolute", "GenuineIntel", [
            ("0000:03:00.0", "0x1002", "0x9999", "0x038000", "amdgpu"),
        ])
        self.assertIn('"host_hardware_selected_gpu_profiles": [\n        "amd"', output)
        self.assertIn('"mesa-libgallium"', output)
        self.assertNotIn('"mesa-va-drivers"', output)
        self.assertIn('"intel-microcode"', output)
        self.assertNotIn('"amd64-microcode"', output)

    def test_explicit_empty_gpu_profiles_disable_gpu_packages(self):
        output = self.run_role_facts("noble", "GenuineIntel", [
            ("0000:04:00.0", "0x8086", "0xabcd", "0x030000", "i915"),
        ], profiles=[])
        self.assertIn('"host_hardware_selected_gpu_profiles": []', output)
        self.assertNotIn('"intel-media-va-driver-non-free"', output)
        self.assertIn('"intel-microcode"', output)

    def test_gpu_tag_dispatch_does_not_select_physical_or_guest_package_lanes(self):
        loader = DataLoader()
        init_plugin_loader()
        play = Play.load({"hosts": "all", "tasks": []}, loader=loader)
        block = Block.load({"block": []}, play=play, loader=loader)
        raw = yaml.safe_load((ROLE_ROOT / "tasks/main.yml").read_text())
        tasks = [Task.load(task, block=block, loader=loader) for task in raw]
        gpu_selected = {task.name for task in tasks if task.evaluate_tags(["gpu"], [], {})}
        self.assertEqual(gpu_selected, {
            "Run host hardware preflight",
            "Configure selected GPU packages",
            "Configure GPU userspace and report detected devices",
        })
        package_selected = {task.name for task in tasks if task.evaluate_tags(["packages"], [], {})}
        self.assertIn("Configure host hardware packages", package_selected)
        self.assertIn("Install physical-host diagnostics", package_selected)
        self.assertIn("Configure KVM guest integration", package_selected)


if __name__ == "__main__":
    unittest.main()
