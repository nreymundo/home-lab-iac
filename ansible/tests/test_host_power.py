"""Temporary-sysfs regression tests for host_power's policy helper."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess


ANSIBLE_ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ANSIBLE_ROOT / "roles/host_power/files/host_power.py"
SPEC = importlib.util.spec_from_file_location("host_power", HELPER_PATH)
host_power = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(host_power)


class HostPowerSysfsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        policy = self.root / "devices/system/cpu/cpufreq/policy2"
        policy.mkdir(parents=True)
        self.put(policy / "scaling_governor", "powersave")
        self.put(policy / "scaling_available_governors", "powersave performance schedutil")
        self.put(policy / "energy_performance_preference", "balance_power")
        self.put(policy / "energy_performance_available_preferences", "performance balance_power power")
        self.put(policy / "scaling_available_governors", "powersave performance schedutil")
        intel = self.root / "devices/system/cpu/intel_pstate"
        intel.mkdir(parents=True)
        self.put(intel / "no_turbo", "0")
        profile = self.root / "firmware/acpi"
        profile.mkdir(parents=True)
        self.put(profile / "platform_profile", "balanced")
        self.put(profile / "platform_profile_choices", "quiet balanced performance")
        constraint = self.root / "class/powercap/intel-rapl:0"
        constraint.mkdir(parents=True)
        self.put(constraint / "name", "package-0")
        self.put(constraint / "constraint_0_name", "long_term")
        self.put(constraint / "constraint_0_power_limit_uw", "30000000")
        self.put(constraint / "constraint_0_min_power_uw", "10000000")
        self.put(constraint / "constraint_0_max_power_uw", "65000000")
        self.put(constraint / "constraint_0_time_window_us", "1000000")
        self.put(constraint / "constraint_0_min_time_window_us", "100000")
        self.put(constraint / "constraint_0_max_time_window_us", "10000000")

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def put(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value + "\n")
        path.chmod(0o644)

    def test_named_rapl_discovery_converts_units_and_reads_back(self):
        config = {"backend": "sysfs", "rapl_limits": [{"zone": "package-0", "constraint": "long_term", "power_limit_w": 42.5, "time_window_s": 2.5}]}
        report = host_power.apply(config, self.root)
        constraint = self.root / "class/powercap/intel-rapl:0"
        self.assertEqual((constraint / "constraint_0_power_limit_uw").read_text().strip(), "42500000")
        self.assertEqual((constraint / "constraint_0_time_window_us").read_text().strip(), "2500000")
        self.assertEqual([row["effective"] for row in report], ["42500000", "2500000"])

    def test_discovers_class_powercap_symlinks_by_zone_name(self):
        backing = self.root / "devices/platform/powercap/rapl-zone"
        backing.mkdir(parents=True)
        self.put(backing / "name", "package-7")
        self.put(backing / "constraint_7_name", "short_term")
        self.put(backing / "constraint_7_power_limit_uw", "20000000")
        class_path = self.root / "class/powercap/intel-rapl:7"
        class_path.parent.mkdir(parents=True, exist_ok=True)
        class_path.symlink_to(backing)
        plan = host_power.validate_rapl(
            [{"zone": "package-7", "constraint": "short_term", "power_limit_w": 25}],
            self.root / "class/powercap",
        )
        self.assertEqual(plan[0][0], class_path / "constraint_7_power_limit_uw")

    def test_readonly_check_is_validating_dryrun_and_does_not_write(self):
        value = self.root / "devices/system/cpu/intel_pstate/no_turbo"
        config = {"backend": "sysfs", "cpu_boost": False}
        report = host_power.apply(config, self.root, check=True)
        self.assertEqual(value.read_text().strip(), "0")
        self.assertEqual(report[0]["effective"], "0")

    def test_rerun_is_idempotent_and_unset_controls_are_untouched(self):
        governor = self.root / "devices/system/cpu/cpufreq/policy2/scaling_governor"
        epp = self.root / "devices/system/cpu/cpufreq/policy2/energy_performance_preference"
        untouched = self.root / "devices/system/cpu/intel_pstate/no_turbo"
        config = {"backend": "sysfs", "cpu_governor": "performance"}
        first = host_power.apply(config, self.root)
        second = host_power.apply(config, self.root)
        self.assertEqual(first[0]["effective"], second[0]["effective"])
        self.assertEqual(governor.read_text().strip(), "performance")
        self.assertEqual(epp.read_text().strip(), "balance_power")
        self.assertEqual(untouched.read_text().strip(), "0")

    def test_validates_all_limits_before_applying_any_control(self):
        governor = self.root / "devices/system/cpu/cpufreq/policy2/scaling_governor"
        config = {"backend": "sysfs", "cpu_governor": "performance", "rapl_limits": [{"zone": "missing", "constraint": "long_term", "power_limit_w": 40}]}
        with self.assertRaisesRegex(host_power.PowerError, "zone 'missing' is missing"):
            host_power.apply(config, self.root)
        self.assertEqual(governor.read_text().strip(), "powersave")

    def test_rejects_ambiguous_zone_and_limit_out_of_range(self):
        with self.assertRaisesRegex(host_power.PowerError, "exceeds hardware maximum"):
            host_power.validate_rapl([{"zone": "package-0", "constraint": "long_term", "power_limit_w": 90}], self.root / "class/powercap")
        second = self.root / "class/powercap/intel-rapl:8"
        second.mkdir(parents=True)
        self.put(second / "name", "package-0")
        self.put(second / "constraint_0_name", "long_term")
        with self.assertRaisesRegex(host_power.PowerError, "zone 'package-0' is ambiguous"):
            host_power.validate_rapl([{"zone": "package-0", "constraint": "long_term", "power_limit_w": 40}], self.root / "class/powercap")

    def test_rejects_boolean_nan_negative_and_overprecision_numbers(self):
        for value in (True, float("nan"), -1, 0, 0.0000001):
            with self.subTest(value=value), self.assertRaises(host_power.PowerError):
                host_power.finite_positive(value, "power_limit_w", 1_000_000)

    def test_readonly_and_unsupported_explicit_controls_fail(self):
        path = self.root / "devices/system/cpu/intel_pstate/no_turbo"
        path.chmod(0o444)
        with self.assertRaisesRegex(host_power.PowerError, "unsupported or read-only"):
            host_power.apply({"backend": "sysfs", "cpu_boost": True}, self.root)
        with self.assertRaisesRegex(host_power.PowerError, "unavailable"):
            host_power.apply({"backend": "sysfs", "platform_profile": "turbo"}, self.root)

    def test_discovery_ignores_device_subsystem_and_cycles(self):
        zone = self.root / "class/powercap/intel-rapl:0"
        (zone / "device").symlink_to(self.root)
        (zone / "subsystem").symlink_to(zone.parent)
        (zone / "intel-rapl:0:0").symlink_to(zone)
        self.put(self.root / "unrelated/name", "package-0")
        self.assertEqual(host_power.discover_zones(zone.parent), [("package-0", zone)])

    def test_control_type_and_class_alias_do_not_duplicate_zone(self):
        powercap = self.root / "class/powercap"
        control = powercap / "intel-rapl"
        self.put(control / "enabled", "1")
        (control / "intel-rapl:0").symlink_to(powercap / "intel-rapl:0")
        self.assertEqual(len(host_power.discover_zones(powercap)), 1)

    def test_epp_advertised_choices_rejected_before_governor_mutation(self):
        governor = self.root / "devices/system/cpu/cpufreq/policy2/scaling_governor"
        with self.assertRaisesRegex(host_power.PowerError, "unavailable"):
            host_power.apply({"backend": "sysfs", "cpu_governor": "performance", "cpu_epp": "invented"}, self.root)
        self.assertEqual(governor.read_text().strip(), "powersave")

    def test_duplicate_constraints_rejected_before_write(self):
        limit = {"zone": "package-0", "constraint": "long_term", "power_limit_w": 40}
        with self.assertRaisesRegex(host_power.PowerError, "Duplicate"):
            host_power.apply({"backend": "sysfs", "rapl_limits": [limit, limit]}, self.root)

    def test_runtime_drift_is_reported_and_repaired(self):
        config = {"backend": "sysfs", "cpu_governor": "performance"}
        self.assertTrue(host_power.apply(config, self.root)[0]["changed"])
        self.assertFalse(host_power.apply(config, self.root)[0]["changed"])
        self.put(self.root / "devices/system/cpu/cpufreq/policy2/scaling_governor", "powersave")
        self.assertTrue(host_power.apply(config, self.root)[0]["changed"])

    def test_ppd_caps_apply_and_invalid_caps_do_not_change_profile(self):
        config = {"backend": "power-profiles-daemon", "profile": "balanced", "rapl_limits": [{"zone": "package-0", "constraint": "long_term", "power_limit_w": 40}]}
        def fake_run(command, **kwargs):
            return subprocess.CompletedProcess(command, 0, "balanced:\npower-saver:\n" if command[-1] == "list" else "balanced", "")
        with patch.object(host_power.subprocess, "run", side_effect=fake_run) as run:
            report = host_power.apply(config, self.root)
            self.assertEqual(report[1]["effective"], "40000000")
            config["rapl_limits"][0]["zone"] = "missing"
            run.reset_mock()
            with self.assertRaises(host_power.PowerError):
                host_power.apply(config, self.root)
            run.assert_not_called()

    def test_ppd_check_does_not_set_profile_or_caps(self):
        config = {"backend": "power-profiles-daemon", "profile": "power-saver", "rapl_limits": [{"zone": "package-0", "constraint": "long_term", "power_limit_w": 40}]}
        def fake_run(command, **kwargs):
            self.assertNotIn("set", command)
            return subprocess.CompletedProcess(command, 0, "balanced:\npower-saver:\n" if command[-1] == "list" else "balanced", "")
        with patch.object(host_power.subprocess, "run", side_effect=fake_run):
            report = host_power.apply(config, self.root, check=True)
            self.assertEqual(report[1]["effective"], "30000000")
            self.assertTrue(report[1]["changed"])

    def test_quantized_rapl_readback_is_reported(self):
        path = self.root / "class/powercap/intel-rapl:0/constraint_0_power_limit_uw"
        with patch.object(host_power, "read", side_effect=["30000000", "39999000"]):
            report = host_power.apply_plan([(path, "40000000")])
        self.assertEqual(report[0]["requested"], "40000000")
        self.assertEqual(report[0]["effective"], "39999000")
        self.assertTrue(report[0]["changed"])

    def test_ppd_profile_readback_and_idempotency(self):
        with tempfile.TemporaryDirectory() as directory:
            command = Path(directory) / "powerprofilesctl"
            state = Path(directory) / "profile"
            state.write_text("balanced")
            command.write_text('#!/bin/sh\ncase "$1" in\nget) cat "$STATE";;\nlist) printf "balanced:\\npower-saver:\\n";;\nset) printf "%s" "$2" > "$STATE";;\nesac\n')
            command.chmod(0o755)
            os.environ["STATE"] = str(state)
            try:
                config = {"backend": "power-profiles-daemon", "profile": "power-saver"}
                self.assertEqual(host_power.apply(config, self.root, powerprofilesctl=str(command))[0]["effective"], "power-saver")
                self.assertEqual(host_power.apply(config, self.root, powerprofilesctl=str(command))[0]["effective"], "power-saver")
            finally:
                os.environ.pop("STATE", None)


if __name__ == "__main__":
    unittest.main()
