"""Offline inventory, lifecycle conditions and unit-rendering regression checks."""
import json
import os
from pathlib import Path
import subprocess
import unittest

import yaml
from ansible.template import Templar, trust_as_template
from jinja2 import Environment

ROOT = Path(__file__).resolve().parents[1]
ENV = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}


def read_yaml(path):
    return yaml.safe_load((ROOT / path).read_text())


def render(value, variables):
    return Templar(variables=variables).template(trust_as_template(value))


def selected(task, variables):
    conditions = task.get("when", [])
    if not isinstance(conditions, list):
        conditions = [conditions]
    templar = Templar(variables=variables)
    return all(templar.evaluate_conditional(trust_as_template(condition)) for condition in conditions)


class UbuntuCompositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(["ansible-inventory", "--list"], env=ENV, capture_output=True, text=True, check=True)
        cls.inventory = json.loads(result.stdout)

    def test_aggregate_has_existing_vm_and_laptop_groups_only(self):
        self.assertEqual(set(self.inventory["ubuntu_hosts"]["children"]), {"all_vms", "headless_laptops", "ubuntu_baremetal"})
        self.assertEqual(set(self.inventory["all_vms"]["children"]), {"development_vms", "hermes_vms", "k3s_nodes", "omniroute_vms"})
        self.assertEqual(self.inventory["headless_laptops"]["hosts"], ["g14-2022"])
        self.assertEqual(set(self.inventory["ubuntu_baremetal"]["children"]), {"k3s_baremetal"})

    def test_daring_is_hand_maintained_ubuntu_baremetal_and_k3s_server(self):
        hosts = self.inventory["_meta"]["hostvars"]
        daring = hosts["daring"]
        self.assertEqual(daring["ansible_host"], "192.168.10.30")
        self.assertEqual(daring["ansible_user"], "ubuntu")
        def group_hosts(name):
            group = self.inventory.get(name, {})
            result = set(group.get("hosts", []))
            for child in group.get("children", []):
                result.update(group_hosts(child))
            return result

        host_groups = {name for name in self.inventory if not name.startswith("_") and "daring" in group_hosts(name)}
        self.assertIn("ubuntu_baremetal", host_groups)
        self.assertIn("k3s_baremetal", host_groups)
        self.assertIn("k3s_server", host_groups)
        self.assertIn("k3s_cluster", host_groups)
        self.assertEqual(daring["k3s_iface"], "enp86s0")
        self.assertEqual(daring["k3s_storage_mode"], "manual")
        self.assertEqual(daring["k3s_storage_expected_uuid"], "bf176804-6285-4d34-842c-c6483255b503")
        self.assertTrue(daring["k3s_allow_workloads"])
        self.assertFalse(daring["swapfile_enabled"])
        self.assertNotIn("k3s_node_labels", daring)
        for key in ("k3s_api_vip", "k3s_join_url", "k3s_admin_api_url"):
            self.assertNotIn(key, daring)
        k3s_defaults = read_yaml("roles/k3s/defaults/main.yml")
        self.assertEqual(k3s_defaults["k3s_node_ip"], "{{ ansible_host }}")
        self.assertEqual(k3s_defaults["k3s_api_vip"], "192.168.10.10")
        for key, value in {
            "host_power_backend": "sysfs",
            "host_power_cpu_governor": "powersave",
            "host_power_cpu_epp": "balance_performance",
            "host_power_cpu_boost": True,
            "host_power_cpu_max_freq_khz": 4200000,
            "host_power_powertop_auto_tune": True,
        }.items():
            self.assertEqual(daring[key], value)
        self.assertEqual(set(daring["host_hardware_extra_packages"]), {"intel-gpu-tools", "ffmpeg"})

    def test_ubuntu_package_additions_are_additive_and_os_scoped(self):
        defaults = read_yaml("roles/common/defaults/main.yml")
        task = next(
            row for row in read_yaml("roles/common/tasks/os-debian.yml")
            if row["name"] == "Install host-specific packages"
        )
        packages_expression = task["ansible.builtin.apt"]["name"]
        self.assertEqual(defaults["common_ubuntu_packages"], [])
        self.assertIn("common_group_packages + common_extra_packages", packages_expression)
        self.assertIn("common_ubuntu_packages if ansible_distribution == 'Ubuntu' else []", packages_expression)
        vm = self.inventory["_meta"]["hostvars"]["vm-dev"]
        self.assertIn("nfs-common", vm["common_group_packages"])
        self.assertEqual(vm.get("common_extra_packages", []), [])
        common_values = {
            "common_group_packages": ["nfs-common"],
            "common_extra_packages": ["host-tool"],
            "common_ubuntu_packages": ["ubuntu-tool"],
        }
        ubuntu_packages = render(packages_expression, {
            **common_values, "ansible_distribution": "Ubuntu",
        })
        debian_packages = render(packages_expression, {
            **common_values, "ansible_distribution": "Debian",
        })
        self.assertEqual(ubuntu_packages, ["nfs-common", "host-tool", "ubuntu-tool"])
        self.assertEqual(debian_packages, ["nfs-common", "host-tool"])
        ubuntu_defaults = read_yaml("inventories/group_vars/ubuntu_hosts.yml")
        package_vars = {**ubuntu_defaults, **self.inventory["_meta"]["hostvars"]["daring"]}
        composed = render(ubuntu_defaults["common_ubuntu_packages"], package_vars)
        self.assertEqual(len(composed), len(set(composed)))
        self.assertIn("bind9-dnsutils", composed)
        self.assertNotIn("dnsutils", composed)
        self.assertNotIn("auditd", composed)

    def test_fleet_defaults_and_explicit_tools_survive_precedence(self):
        hosts = self.inventory["_meta"]["hostvars"]
        for name in ["vm-dev", "vm-hermes", "vm-omniroute", "k3s-node-01", "g14-2022"]:
            with self.subTest(name=name):
                values = hosts[name]
                self.assertFalse(values["common_run_upgrade"])
                self.assertFalse(values["common_unattended_upgrades_auto_reboot"])
                self.assertTrue(values["common_passwordless_sudo"])
                self.assertFalse(values["cockpit_enabled"])
        self.assertTrue(hosts["vm-dev"]["homebrew_install_enabled"])
        self.assertTrue(hosts["g14-2022"]["nodejs_runtime_install_enabled"])
        self.assertTrue(hosts["vm-omniroute"]["ufw_enabled"])
        self.assertNotIn("common_passwordless_sudo", hosts["pve3"])
        self.assertIn("nfs-common", hosts["k3s-node-01"]["common_group_packages"])
        self.assertIn("intel-gpu-tools", hosts["k3s-node-01"]["common_extra_packages"])

    def test_unified_playbook_limits_preserve_target_sets(self):
        def group_hosts(name):
            group = self.inventory[name]
            hosts = set(group.get("hosts", []))
            for child in group.get("children", []):
                hosts.update(group_hosts(child))
            return hosts

        for target in ["all_vms", "headless_laptops"]:
            with self.subTest(target=target):
                result = subprocess.run(
                    ["ansible-playbook", str(ROOT / "playbooks/ubuntu.yml"), "--limit", target, "--list-hosts"],
                    env=ENV, capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                actual = {line.strip() for line in result.stdout.splitlines() if line.startswith("      ")}
                expected = group_hosts(target)
                self.assertTrue(expected)
                self.assertEqual(actual, expected)

    def test_rendered_pi_update_origins_preserve_non_ubuntu_repositories(self):
        defaults = read_yaml("roles/common/defaults/main.yml")
        template = (ROOT / "roles/common/templates/50unattended-upgrades.j2").read_text()
        values = {**defaults, **self.inventory["_meta"]["hostvars"]["main-rpi4"]}
        config = render(template, values)
        for origin in [
            "origin=Debian,codename=${distro_codename},label=Debian",
            "origin=Debian,codename=${distro_codename},label=Debian-Security",
            "origin=Raspbian,codename=${distro_codename},label=Raspbian",
            "origin=Raspberry Pi Foundation,codename=${distro_codename},label=Raspberry Pi Foundation",
        ]:
            self.assertIn(f'"{origin}";', config)
        self.assertNotIn("origin=Ubuntu", config)
        ubuntu_config = render(template, {**defaults, **self.inventory["_meta"]["hostvars"]["k3s-node-01"]})
        self.assertIn('"origin=Ubuntu,archive=${distro_codename}-security";', ubuntu_config)
        self.assertNotIn("origin=Raspbian", ubuntu_config)

    def test_optional_role_conditions_and_tags(self):
        roles = read_yaml("playbooks/ubuntu.yml")[0]["roles"]
        for role_name, toggle in [("nodejs_runtime", "nodejs_runtime_install_enabled"), ("docker", "docker_install_enabled"), ("ufw", "ufw_install_enabled"), ("fail2ban", "fail2ban_install_enabled"), ("disk_expand", "disk_expand_rootfs_expand")]:
            role = next(row for row in roles if row["role"] == role_name)
            self.assertFalse(selected(role, {toggle: False}))
            self.assertTrue(selected(role, {toggle: True}))
            self.assertTrue(role["tags"])
        # Always enter lifecycle-owning roles so disabling can remove old state.
        for name in ["host_power", "cockpit"]:
            self.assertNotIn("when", next(row for row in roles if row["role"] == name))

    def test_asus_fan_helper_does_not_write_platform_profile(self):
        script = (ROOT / "roles/headless_laptop/templates/asus-quiet-fan-policy.j2").read_text()
        self.assertIn('read -r profile < "$PROFILE_FILE"', script)
        self.assertNotIn('> "$PROFILE_FILE"', script)


class PolicyLifecycleTests(unittest.TestCase):
    def test_k3s_unit_requires_manual_storage_mount_only(self):
        template = (ROOT / "roles/k3s/templates/k3s.service.j2").read_text()
        values = {"k3s_exec_args": "server", "k3s_storage_path": "/var/lib/longhorn"}
        manual = render(template, {**values, "k3s_storage_mode": "manual"})
        managed = render(template, {**values, "k3s_storage_mode": "managed"})
        self.assertIn("RequiresMountsFor=/var/lib/longhorn", manual)
        self.assertNotIn("RequiresMountsFor=", managed)

    def test_ppd_relinquishment_only_when_previously_managed(self):
        tasks = read_yaml("roles/host_power/tasks/policy.yml")
        task = next(row for row in tasks if row["name"] == "Relinquish previously managed PPD backend")
        for previous, current, expected in [("none", "none", False), ("power-profiles-daemon", "none", True), ("sysfs", "none", False), ("power-profiles-daemon", "power-profiles-daemon", False)]:
            values = {"host_power_previous_backend": previous, "host_power_backend": current, "ansible_facts": {"services": {"power-profiles-daemon.service": {}}}}
            self.assertEqual(selected(task, values), expected)

    def test_competitor_stop_filters_missing_units_and_keeps_errors(self):
        task = next(row for row in read_yaml("roles/host_power/tasks/policy.yml") if row["name"] == "Stop competing policy controllers")
        self.assertNotIn("failed_when", task)
        values = {"host_power_backend": "sysfs", "host_power_known_competing_services": ["tlp.service"], "ansible_facts": {"services": {"tlp.service": {}}}}
        self.assertIn("power-profiles-daemon.service", render(task["loop"], values))
        self.assertTrue(selected(task, {**values, "item": "tlp.service"}))
        self.assertFalse(selected(task, {**values, "item": "tuned.service"}))
        self.assertFalse(selected(task, {**values, "item": "tlp.service", "host_power_backend": "none"}))

    def test_runtime_convergence_runs_even_with_unchanged_files(self):
        task = next(row for row in read_yaml("roles/host_power/tasks/policy.yml") if row["name"] == "Reconverge runtime policy and report effective controls")
        self.assertTrue(selected(task, {"host_power_backend": "sysfs", "ansible_check_mode": False}))
        for changed in [True, False]:
            templar = Templar(variables={"host_power_result": {"stdout": json.dumps([{"changed": changed}])}})
            self.assertEqual(templar.evaluate_conditional(trust_as_template(task["changed_when"])), changed)

    def test_cockpit_firewall_sources_removed_on_disable_or_change(self):
        task = next(row for row in read_yaml("roles/cockpit/tasks/main.yml") if row["name"] == "Remove obsolete Cockpit firewall rules")
        previous = {"sources": ["192.168.10.0/24", "192.168.1.0/24"]}
        for enabled, expected in [(False, previous["sources"]), (True, ["192.168.1.0/24"])]:
            actual = render(task["loop"], {"cockpit_previous": previous, "cockpit_enabled": enabled, "cockpit_ufw_sources": ["192.168.10.0/24"]})
            self.assertEqual(set(actual), set(expected))

    def test_cockpit_disable_stops_socket_and_leaves_never_managed_install_alone(self):
        task = next(row for row in read_yaml("roles/cockpit/tasks/main.yml") if row["name"] == "Stop previously managed Cockpit access when disabled")
        for managed in [True, False]:
            self.assertEqual(selected(task, {"cockpit_enabled": False, "cockpit_state_file": {"stat": {"exists": managed}}, "item": {"item": "cockpit.socket", "stdout": "loaded"}}), managed)

    def test_systemd_unit_lines_survive_ansible_whitespace_rules(self):
        environment = Environment(trim_blocks=True, keep_trailing_newline=True)
        for backend in ["sysfs", "power-profiles-daemon", "none"]:
            for name in ["host-power-policy.service", "host-power-powertop.service"]:
                template = environment.from_string((ROOT / f"roles/host_power/templates/{name}.j2").read_text())
                rendered = template.render(host_power_backend=backend)
                self.assertIn("\n[Service]\n", rendered)
                self.assertIn("\n[Install]\n", rendered)
                lines = rendered.splitlines()
                self.assertTrue(any(line.startswith("After=local-fs.target") or line == "After=host-power-policy.service" for line in lines))
                self.assertNotIn("After=multi-user.target", rendered)
                if name == "host-power-policy.service" and backend == "power-profiles-daemon":
                    self.assertIn("After=local-fs.target power-profiles-daemon.service", lines)
                    self.assertIn("Requires=power-profiles-daemon.service", lines)


if __name__ == "__main__":
    unittest.main()
