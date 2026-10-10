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
        self.put(policy / "cpuinfo_max_freq", "5200000")
        self.put(policy / "scaling_min_freq", "800000")
        self.put(policy / "scaling_max_freq", "5000000")
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
        with patch.object(host_power, "read", side_effect=["30000000", "30000000", "39999000"]):
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

    def add_cpu_policy(self, name, hardware_max, minimum="800000", maximum="5000000"):
        policy = self.root / "devices/system/cpu/cpufreq" / name
        policy.mkdir(parents=True, exist_ok=True)
        self.put(policy / "cpuinfo_max_freq", str(hardware_max))
        self.put(policy / "scaling_min_freq", str(minimum))
        self.put(policy / "scaling_max_freq", str(maximum))
        return policy

    def test_cpu_frequency_ceiling_selects_only_policy_above_strict_threshold(self):
        p_like = self.add_cpu_policy("policy0", 5200000)
        e_like = self.add_cpu_policy("policy4", 4200000, maximum="4200000")
        lower = self.add_cpu_policy("policy6", 3800000, maximum="3800000")
        self.put(self.root / "devices/system/cpu/cpufreq/policy2/cpuinfo_max_freq", "4200000")
        self.put(self.root / "devices/system/cpu/cpufreq/policy2/scaling_max_freq", "4200000")
        config = {"backend": "sysfs", "cpu_max_freq_khz": 4200000}
        first = host_power.apply(config, self.root)
        second = host_power.apply(config, self.root)
        self.assertEqual((p_like / "scaling_max_freq").read_text().strip(), "4200000")
        self.assertEqual((e_like / "scaling_max_freq").read_text().strip(), "4200000")
        self.assertEqual((lower / "scaling_max_freq").read_text().strip(), "3800000")
        self.assertEqual(len(first), 1)
        self.assertTrue(first[0]["changed"])
        self.assertFalse(second[0]["changed"])
        self.put(p_like / "scaling_max_freq", "5000000")
        self.assertTrue(host_power.apply(config, self.root)[0]["changed"])
        self.assertEqual((p_like / "scaling_max_freq").read_text().strip(), "4200000")

    def test_cpu_frequency_ceiling_check_mode_and_unset_are_non_mutating(self):
        policy = self.add_cpu_policy("policy0", 5200000)
        config = {"backend": "sysfs", "cpu_max_freq_khz": 4200000}
        report = host_power.apply(config, self.root, check=True)
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "5000000")
        self.assertTrue(report[0]["changed"])
        host_power.apply({"backend": "sysfs"}, self.root)
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "5000000")

    def test_cpu_frequency_ceiling_rejects_invalid_values_and_missing_policies(self):
        for value in (True, False, 0, -1, 4.2, float("nan"), float("inf"), "not-a-number"):
            with self.subTest(value=value), self.assertRaises(host_power.PowerError):
                host_power.apply({"backend": "sysfs", "cpu_max_freq_khz": value}, self.root)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(host_power.PowerError, "no cpufreq policy"):
                host_power.apply({"backend": "sysfs", "cpu_max_freq_khz": 4200000}, Path(directory))

    def test_cpu_frequency_ceiling_validates_selected_controls_and_bounds(self):
        policy = self.add_cpu_policy("policy0", 5200000)
        with self.subTest("minimum bound"), self.assertRaisesRegex(host_power.PowerError, "below scaling_min_freq"):
            host_power.apply({"backend": "sysfs", "cpu_max_freq_khz": 700000}, self.root)
        minimum = policy / "scaling_min_freq"
        minimum.unlink()
        with self.subTest("missing minimum"), self.assertRaisesRegex(host_power.PowerError, "missing or read-only"):
            host_power.apply({"backend": "sysfs", "cpu_max_freq_khz": 4200000}, self.root)
        self.put(minimum, "800000")
        maximum = policy / "scaling_max_freq"
        maximum.chmod(0o444)
        with self.subTest("read-only maximum"), self.assertRaisesRegex(host_power.PowerError, "missing or read-only"):
            host_power.apply({"backend": "sysfs", "cpu_max_freq_khz": 4200000}, self.root)
        maximum.chmod(0o644)
        self.put(policy / "cpuinfo_max_freq", "malformed")
        with self.subTest("malformed hardware maximum"), self.assertRaisesRegex(host_power.PowerError, "Malformed"):
            host_power.apply({"backend": "sysfs", "cpu_max_freq_khz": 4200000}, self.root)

    def test_cpu_frequency_ceiling_validates_every_policy_before_any_write(self):
        first = self.add_cpu_policy("policy0", 5200000)
        later = self.add_cpu_policy("policy3", 5300000)
        self.put(later / "scaling_min_freq", "broken")
        self.put(later / "scaling_governor", "powersave")
        self.put(later / "scaling_available_governors", "powersave performance schedutil")
        governor = first / "scaling_governor"
        self.put(governor, "powersave")
        with self.assertRaisesRegex(host_power.PowerError, "Malformed CPU frequency policy"):
            host_power.apply({"backend": "sysfs", "cpu_governor": "performance", "cpu_max_freq_khz": 4200000}, self.root)
        self.assertEqual(governor.read_text().strip(), "powersave")
        self.assertEqual((first / "scaling_max_freq").read_text().strip(), "5000000")

    def test_boost_is_planned_before_cpu_frequency_ceiling(self):
        policy = self.add_cpu_policy("policy0", 5200000)
        report = host_power.apply({"backend": "sysfs", "cpu_boost": False, "cpu_max_freq_khz": 4200000}, self.root)
        self.assertIn("no_turbo", report[0]["path"])
        self.assertIn("scaling_max_freq", report[1]["path"])
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "4200000")

    def test_cpu_frequency_ceiling_rechecks_after_boost_resets_existing_limit(self):
        policy = self.add_cpu_policy("policy0", 5200000, maximum="4200000")
        boost = self.root / "devices/system/cpu/intel_pstate/no_turbo"
        original_write_text = Path.write_text

        def write_with_boost_reset(path, data, *args, **kwargs):
            result = original_write_text(path, data, *args, **kwargs)
            if path == boost:
                original_write_text(policy / "scaling_max_freq", "5200000\n")
            return result

        with patch.object(Path, "write_text", write_with_boost_reset):
            report = host_power.apply({"backend": "sysfs", "cpu_boost": False, "cpu_max_freq_khz": 4200000}, self.root)
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "4200000")
        self.assertTrue(report[1]["changed"])
        self.assertEqual(report[1]["effective"], "4200000")

    def test_check_mode_and_unchanged_boost_do_not_write_or_reapply_existing_ceiling(self):
        policy = self.add_cpu_policy("policy0", 5200000, maximum="4200000")
        self.put(self.root / "devices/system/cpu/cpufreq/policy2/cpuinfo_max_freq", "4200000")
        self.put(self.root / "devices/system/cpu/cpufreq/policy2/scaling_max_freq", "4200000")
        boost = self.root / "devices/system/cpu/intel_pstate/no_turbo"
        self.put(boost, "1")  # cpu_boost=False already matches Intel's inverted control.
        config = {"backend": "sysfs", "cpu_boost": False, "cpu_max_freq_khz": 4200000}
        with patch.object(Path, "write_text", side_effect=AssertionError("check mode wrote sysfs")):
            report = host_power.apply(config, self.root, check=True)
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "4200000")
        self.assertFalse(report[0]["changed"])
        self.assertFalse(report[1]["changed"])
        with patch.object(Path, "write_text", side_effect=AssertionError("unchanged controls were rewritten")):
            report = host_power.apply(config, self.root)
        self.assertFalse(report[0]["changed"])
        self.assertFalse(report[1]["changed"])

    def test_scaling_max_freq_retries_stale_readback_until_exact_value(self):
        path = self.root / "devices/system/cpu/cpufreq/policy2/scaling_max_freq"
        readback = iter(("5000000", "5000000", "4900000", "4900000", "4200000"))
        with patch.object(host_power, "read", side_effect=lambda _path: next(readback)), patch.object(host_power.time, "sleep") as sleep:
            report = host_power.apply_plan([(path, "4200000")])
        self.assertEqual(report[0]["effective"], "4200000")
        self.assertTrue(report[0]["changed"])
        self.assertEqual(sleep.call_count, 2)

    def test_scaling_max_freq_persistent_mismatch_fails_after_bounded_retries(self):
        path = self.root / "devices/system/cpu/cpufreq/policy2/scaling_max_freq"

        def stale_read(read_path):
            if read_path == path:
                return "4900000"
            return host_power.read(read_path)

        with patch.object(host_power, "read", side_effect=stale_read), patch.object(host_power.time, "sleep") as sleep:
            with self.assertRaisesRegex(host_power.PowerError, "Readback '4900000' differs from requested '4200000'"):
                host_power.apply_plan([(path, "4200000")])
        self.assertEqual(sleep.call_count, 20)

    def test_readback_retry_is_skipped_for_check_unchanged_and_other_controls(self):
        path = self.root / "devices/system/cpu/cpufreq/policy2/scaling_max_freq"
        with patch.object(host_power.time, "sleep") as sleep:
            check_report = host_power.apply_plan([(path, "5000000")], check=True)
            unchanged_report = host_power.apply_plan([(path, "5000000")])
            self.assertFalse(check_report[0]["changed"])
            self.assertFalse(unchanged_report[0]["changed"])
            sleep.assert_not_called()

        governor = self.root / "devices/system/cpu/cpufreq/policy2/scaling_governor"
        def stale_governor_read(read_path):
            return "powersave" if read_path == governor else host_power.read(read_path)
        with patch.object(host_power, "read", side_effect=stale_governor_read), patch.object(host_power.time, "sleep") as sleep:
            with self.assertRaisesRegex(host_power.PowerError, "Readback 'powersave' differs"):
                host_power.apply_plan([(governor, "performance")])
            sleep.assert_not_called()

    def test_ppd_rejects_explicit_falsy_cpu_frequency_ceiling_before_commands(self):
        for cap in (0, ""):
            with self.subTest(cap=cap), patch.object(host_power.subprocess, "run") as run:
                with self.assertRaisesRegex(host_power.PowerError, "mutually exclusive"):
                    host_power.apply({"backend": "power-profiles-daemon", "cpu_max_freq_khz": cap}, self.root)
                run.assert_not_called()

    def test_ppd_rejects_valid_cpu_frequency_ceiling_before_commands(self):
        with patch.object(host_power.subprocess, "run") as run:
            with self.assertRaisesRegex(host_power.PowerError, "mutually exclusive"):
                host_power.apply({"backend": "power-profiles-daemon", "cpu_max_freq_khz": 4200000}, self.root)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
