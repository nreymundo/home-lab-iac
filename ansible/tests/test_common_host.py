"""Offline regression tests for common host GRUB and sshd configuration."""

import shutil
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from ansible.parsing.dataloader import DataLoader
from ansible.plugins.loader import init_plugin_loader
from ansible.playbook.block import Block
from ansible.playbook.play import Play
from ansible.playbook.task import Task
from jinja2 import Environment
import yaml


ANSIBLE_ROOT = Path(__file__).resolve().parents[1]


def template_environment():
    environment = Environment()
    environment.filters["to_json"] = json.dumps
    environment.filters["regex_replace"] = lambda value, pattern, replacement="": re.sub(pattern, replacement, value)
    environment.filters["unique"] = lambda values: list(dict.fromkeys(values))
    return environment


class CommonGrubParameterTests(unittest.TestCase):
    def render_dropin(self, add, remove):
        template_path = ANSIBLE_ROOT / "roles/common/templates/99-ansible-kernel-params.cfg.j2"
        template = template_environment().from_string(template_path.read_text())
        return template.render(common_grub_add=add, common_grub_remove=remove)

    def compose(self, existing, add, remove, after_source=""):
        with tempfile.TemporaryDirectory() as temporary_directory:
            dropin = Path(temporary_directory) / "grub.cfg"
            dropin.write_text(self.render_dropin(add, remove))
            Path(temporary_directory, "expand-me").touch()
            result = subprocess.run(
                ["bash", "-c", 'GRUB_CMDLINE_LINUX_DEFAULT="$1"; source "$2"; printf "%s\\n" "$GRUB_CMDLINE_LINUX_DEFAULT"; ' + after_source, "test", existing, str(dropin)],
                check=True,
                capture_output=True,
                text=True,
                cwd=temporary_directory,
            )
            return result.stdout.strip().split()

    def test_preserves_unmanaged_and_critical_args_while_replacing_managed_key(self):
        result = self.compose(
            "quiet root=UUID=abc crashkernel=1G-4G:192M foo=old",
            ["foo=new", "intel_iommu=on"],
            [],
        )
        self.assertEqual(result, ["quiet", "root=UUID=abc", "crashkernel=1G-4G:192M", "foo=new", "intel_iommu=on"])

    def test_removes_requested_key_without_touching_other_arguments(self):
        result = self.compose("quiet foo=old splash", [], ["foo"])
        self.assertEqual(result, ["quiet", "splash"])

    def test_add_replaces_existing_value_and_deduplicates_key(self):
        result = self.compose("quiet foo=old foo=older", ["foo=new"], [])
        self.assertEqual(result, ["quiet", "foo=new"])

    def test_later_requested_value_wins_for_duplicate_added_key(self):
        result = self.compose("quiet", ["foo=first", "bar=one", "foo=last"], [])
        self.assertEqual(result, ["quiet", "bar=one", "foo=last"])

    def test_source_does_not_leak_noglob_into_grub_caller(self):
        expanded = self.compose("quiet", [], [], 'printf "%s\\n" *')
        self.assertIn("expand-me", expanded)
        self.assertNotIn("*", expanded)

    def test_protected_kernel_keys_reject_bare_and_valued_forms(self):
        tasks = yaml.safe_load((ANSIBLE_ROOT / "roles/common/tasks/grub.yml").read_text())
        protected_pattern = tasks[1]["ansible.builtin.assert"]["that"][-1].split("match('", 1)[1].split("')", 1)[0]
        for token in ("root", "root=UUID=abc", "resume", "resume=UUID=abc", "rd.luks", "rd.luks=1", "init", "systemd.unit", "BOOT_IMAGE"):
            self.assertRegex(token, protected_pattern)
        for token in ("quiet", "intel_iommu=on", "foo=bar"):
            self.assertNotRegex(token, protected_pattern)

    def test_empty_parameter_configuration_removes_managed_dropin(self):
        tasks = yaml.safe_load((ANSIBLE_ROOT / "roles/common/tasks/grub.yml").read_text())
        removal = tasks[3]
        self.assertEqual(removal["ansible.builtin.file"]["state"], "absent")
        self.assertIn("common_grub_add | length == 0", removal["when"])
        self.assertIn("common_grub_remove | length == 0", removal["when"])

    def test_grub_reboot_marker_survives_unchanged_role_rerun_until_reboot(self):
        tasks = yaml.safe_load((ANSIBLE_ROOT / "roles/common/tasks/os-debian.yml").read_text())
        marker_task = next(task for task in tasks if task["name"] == "Check for pending common-role GRUB reboot marker")
        self.assertEqual(marker_task["ansible.builtin.stat"]["path"], "/run/common-role-grub-reboot-required")
        handler_text = (ANSIBLE_ROOT / "roles/common/handlers/main.yml").read_text()
        self.assertIn("common-role-grub-reboot-required", handler_text)

    def test_os_task_tags_isolate_packages_and_boot_for_both_families(self):
        loader = DataLoader()
        init_plugin_loader()
        play = Play.load({"hosts": "all", "tasks": []}, loader=loader)
        block = Block.load({"block": []}, play=play, loader=loader)
        cases = {
            "os-debian.yml": {
                "boot": {"Configure Ubuntu GRUB kernel parameters", "Check for reboot-required marker", "Check for pending common-role GRUB reboot marker", "Report whether this host requires a reboot"},
                "packages": {"Update apt cache and upgrade packages", "Refresh apt package indices when full upgrade is disabled", "Install common packages", "Install unattended upgrade dependencies"},
            },
            "os-fedora.yml": {
                "boot": {"Merge desired kernel parameter lists", "Validate kernel params do not touch protected keys", "Add kernel parameters"},
                "packages": {"Update dnf cache and upgrade packages", "Install common packages", "Install dnf-automatic"},
            },
        }
        forbidden_names = {
            "boot": {
                "Install common packages", "Install host-specific packages", "Install Mosh",
                "Install sudo before validating managed sudo policy",
                "Ensure systemd-timesyncd is installed", "Install unattended upgrade dependencies",
                "Update apt cache and upgrade packages", "Refresh apt package indices when full upgrade is disabled",
                "Update dnf cache and upgrade packages", "Ensure chrony is installed", "Install dnf-automatic",
                "Configure managed sudo policy", "Configure netplan when provided",
                "Configure NetworkManager ethernet connections", "Configure NetworkManager VLAN connections",
                "Stop and mask firewalld",
            },
            "packages": {"Configure Ubuntu GRUB kernel parameters", "Merge desired kernel parameter lists"},
        }

        for filename, expected in cases.items():
            raw_tasks = yaml.safe_load((ANSIBLE_ROOT / "roles/common/tasks" / filename).read_text())
            loaded = [Task.load(item, block=block, loader=loader) for item in raw_tasks]
            names_by_tag = {
                tag: {task.name for task in loaded if task.evaluate_tags([tag], [], {})}
                for tag in ("boot", "packages", "base")
            }
            for tag, names in expected.items():
                self.assertTrue(names.issubset(names_by_tag[tag]), f"{filename} missing {tag} tasks: {names - names_by_tag[tag]}")
                self.assertFalse(forbidden_names[tag] & names_by_tag[tag], f"{filename} selected unrelated {tag} tasks")

            # The dispatch include is reachable under each explicit category,
            # but does not apply those tags to every task in the OS file.
            dispatch = next(
                item for item in yaml.safe_load((ANSIBLE_ROOT / "roles/common/tasks/main.yml").read_text())
                if item.get("ansible.builtin.include_tasks", {}).get("file") == filename
            )
            self.assertEqual(set(dispatch["tags"]), {"base", "packages", "boot"})
            self.assertNotIn("apply", dispatch["ansible.builtin.include_tasks"])

    def test_apt_timer_tasks_preserve_admin_override_through_schedule_lifecycle(self):
        tasks_path = ANSIBLE_ROOT / "roles/common/tasks/apt-timers.yml"
        tasks = yaml.safe_load(tasks_path.read_text())
        defaults = yaml.safe_load((ANSIBLE_ROOT / "roles/common/defaults/main.yml").read_text())
        self.assertEqual(defaults["common_apt_daily_timer_schedule"], "")
        self.assertEqual(defaults["common_apt_daily_upgrade_timer_schedule"], "")

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            admin_override = root / "etc/systemd/system/apt-daily.timer.d/override.conf"
            admin_override.parent.mkdir(parents=True)
            admin_override.write_text("# administrator-owned\n[Timer]\nOnCalendar=daily\n")

            transformed = []
            for task in tasks:
                rewritten = json.loads(json.dumps(task))
                # Execute these repository tasks unchanged apart from redirecting
                # system paths into the isolated temporary root and suppressing
                # host-level systemd handler calls.
                text = json.dumps(rewritten).replace("/etc/", f"{root}/etc/")
                rewritten = json.loads(text)
                rewritten.pop("notify", None)
                for module in ("ansible.builtin.file", "ansible.builtin.copy"):
                    if module in rewritten:
                        rewritten[module].pop("owner", None)
                        rewritten[module].pop("group", None)
                if rewritten.get("ansible.builtin.meta") == "flush_handlers":
                    continue
                transformed.append(rewritten)

            playbook = root / "apt-timers-test.yml"
            playbook.write_text(yaml.safe_dump([{
                "hosts": "localhost",
                "gather_facts": False,
                "connection": "local",
                "become": False,
                "tasks": transformed,
            }], sort_keys=False))
            inventory = root / "inventory.yml"
            inventory.write_text("all:\n  hosts:\n    localhost:\n      ansible_connection: local\n")
            vars_file = root / "vars.json"

            def run_schedules(daily, upgrade):
                vars_file.write_text(json.dumps({
                    "common_apt_daily_timer_schedule": daily,
                    "common_apt_daily_upgrade_timer_schedule": upgrade,
                }))
                environment = os.environ.copy()
                environment["ANSIBLE_CONFIG"] = str(ANSIBLE_ROOT / "ansible.cfg")
                result = subprocess.run(
                    ["ansible-playbook", "-i", str(inventory), str(playbook), "-e", f"@{vars_file}"],
                    check=False,
                    capture_output=True,
                    text=True,
                    env=environment,
                )
                if result.returncode != 0:
                    self.fail(f"Ansible timer task fixture failed:\n{result.stdout}\n{result.stderr}")
                return result.stdout

            admin_content = admin_override.read_text()
            run_schedules("", "")  # unset
            role_override = admin_override.parent / "90-ansible-common-schedule.conf"
            self.assertFalse(role_override.exists())
            self.assertEqual(admin_override.read_text(), admin_content)

            run_schedules("*-*-* 03:00:00", "")  # configure
            self.assertIn("OnCalendar=*-*-* 03:00:00", role_override.read_text())
            self.assertEqual(admin_override.read_text(), admin_content)

            run_schedules("*-*-* 04:00:00", "")  # change
            self.assertIn("OnCalendar=*-*-* 04:00:00", role_override.read_text())
            self.assertEqual(admin_override.read_text(), admin_content)

            unchanged = run_schedules("*-*-* 04:00:00", "")  # repeat unchanged
            self.assertIn("changed=0", unchanged)
            run_schedules("", "")  # unset again
            self.assertFalse(role_override.exists())
            self.assertEqual(admin_override.read_text(), admin_content)


@unittest.skipUnless(shutil.which("sshd") and shutil.which("ssh-keygen"), "OpenSSH server tools are unavailable")
class SshdPrecedenceTests(unittest.TestCase):
    def test_rendered_early_dropin_wins_over_cloud_init_dropin(self):
        template_path = ANSIBLE_ROOT / "roles/ssh_hardening/templates/00-ansible-hardening.conf.j2"
        template = template_environment().from_string(template_path.read_text())
        hardening = template.render(ssh_hardening_sshd_settings_effective={
            "PermitRootLogin": "without-password",
            "ChallengeResponseAuthentication": "no",
        })

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            dropins = root / "sshd_config.d"
            dropins.mkdir()
            (dropins / "00-ansible-hardening.conf").write_text(hardening)
            (dropins / "50-cloud-init.conf").write_text("PermitRootLogin yes\n")
            host_key = root / "host_key"
            subprocess.run(
                [shutil.which("ssh-keygen"), "-q", "-t", "ed25519", "-N", "", "-f", str(host_key)],
                check=True,
                capture_output=True,
                text=True,
            )
            config = root / "sshd_config"
            config.write_text(f"Include {dropins}/*.conf\nHostKey {host_key}\nPermitRootLogin yes\nChallengeResponseAuthentication yes\n")
            result = subprocess.run(
                [shutil.which("sshd"), "-T", "-f", str(config)],
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertIn("permitrootlogin prohibit-password", result.stdout.lower().replace("without-password", "prohibit-password").splitlines())
        self.assertIn("kbdinteractiveauthentication no", result.stdout.lower().splitlines())

    def test_ssh_assertion_evaluates_aliases_and_mismatches(self):
        tasks = yaml.safe_load((ANSIBLE_ROOT / "roles/ssh_hardening/tasks/ssh.yml").read_text())
        checks = next(task for task in tasks if task["name"] == "Assert effective sshd settings match requested hardening policy")
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            playbook = root / "ssh-assertion-test.yml"
            inventory = root / "inventory.yml"
            inventory.write_text("all:\n  hosts:\n    localhost:\n      ansible_connection: local\n")

            def assertion_passes(output, key, value):
                task = json.loads(json.dumps(checks))
                task["loop"] = [{"key": key, "value": value}]
                task["when"] = True
                playbook.write_text(yaml.safe_dump([{
                    "hosts": "localhost",
                    "gather_facts": False,
                    "connection": "local",
                    "vars": {"ssh_hardening_effective_sshd": {"stdout": output}},
                    "tasks": [task],
                }], sort_keys=False))
                result = subprocess.run(
                    ["ansible-playbook", "-i", str(inventory), str(playbook)],
                    capture_output=True,
                    text=True,
                    env={**os.environ, "ANSIBLE_CONFIG": str(ANSIBLE_ROOT / "ansible.cfg")},
                )
                return result.returncode == 0

            self.assertTrue(assertion_passes("kbdinteractiveauthentication no\n", "ChallengeResponseAuthentication", "no"))
            self.assertTrue(assertion_passes("kbdinteractiveauthentication no\n", "KbdInteractiveAuthentication", "no"))
            self.assertTrue(assertion_passes("permitrootlogin prohibit-password\n", "PermitRootLogin", "without-password"))
            self.assertFalse(assertion_passes("kbdinteractiveauthentication yes\n", "ChallengeResponseAuthentication", "no"))
            self.assertFalse(assertion_passes("permitrootlogin yes\n", "PermitRootLogin", "without-password"))
            self.assertFalse(assertion_passes("", "PasswordAuthentication", "no"))

    def test_hushlogin_uses_copy_dest(self):
        tasks = yaml.safe_load((ANSIBLE_ROOT / "roles/ssh_hardening/tasks/ssh.yml").read_text())
        copy_task = next(task for task in tasks if task["name"] == "Ensure hush login file exists")
        self.assertIn("dest", copy_task["ansible.builtin.copy"])
        self.assertNotIn("path", copy_task["ansible.builtin.copy"])


if __name__ == "__main__":
    unittest.main()
