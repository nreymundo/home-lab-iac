#!/usr/bin/env python3
"""Apply and report a named, persistent host power policy."""

import argparse
import json
import os
from decimal import Decimal, InvalidOperation
from pathlib import Path
import subprocess
import sys


class PowerError(ValueError):
    """Invalid or unsupported requested power control."""


def read(path):
    try:
        return path.read_text().strip()
    except OSError as error:
        raise PowerError(f"Cannot read {path}: {error}") from error


def writable(path):
    try:
        mode = path.stat().st_mode
    except OSError:
        return False
    return bool(mode & 0o222)


def finite_positive(value, label, scale):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise PowerError(f"{label} must be a finite positive number")
    try:
        decimal = Decimal(str(value))
    except InvalidOperation as error:
        raise PowerError(f"{label} must be a finite positive number") from error
    if not decimal.is_finite() or decimal <= 0:
        raise PowerError(f"{label} must be a finite positive number")
    scaled = decimal * scale
    if scaled != scaled.to_integral_value():
        raise PowerError(f"{label} has more precision than sysfs supports")
    return int(scaled)


def discover_zones(powercap):
    matches = []
    seen = set()
    pending = list(powercap.iterdir()) if powercap.exists() else []
    while pending:
        path = pending.pop()
        try:
            resolved = path.resolve()
            identity = str(resolved)
            if identity in seen:
                continue
            seen.add(identity)
            if not path.is_dir():
                continue
            name_file = path / "name"
            if name_file.is_file():
                name = read(name_file)
                if name.startswith("package-"):
                    matches.append((name, path))
            pending.extend(path.iterdir())
        except OSError as error:
            raise PowerError(f"Cannot discover powercap sysfs under {path}: {error}") from error
    return matches


def validate_rapl(entries, powercap):
    if not isinstance(entries, list):
        raise PowerError("rapl_limits must be a list")
    plans = []
    zone_matches = discover_zones(powercap)
    for entry in entries:
        if not isinstance(entry, dict):
            raise PowerError("Each RAPL limit must be a mapping")
        zone_name = entry.get("zone")
        constraint_name = entry.get("constraint")
        if not isinstance(zone_name, str) or not zone_name or not isinstance(constraint_name, str) or not constraint_name:
            raise PowerError("Each RAPL limit requires non-empty zone and constraint names")
        zones = [path for name, path in zone_matches if name == zone_name]
        if len(zones) != 1:
            raise PowerError(f"RAPL zone {zone_name!r} is {'missing' if not zones else 'ambiguous'}")
        zone = zones[0]
        constraint_dirs = []
        for path in zone.glob("constraint_*"):
            name_file = path / "name"
            if name_file.is_file() and read(name_file) == constraint_name:
                constraint_dirs.append(path)
        if len(constraint_dirs) != 1:
            raise PowerError(f"RAPL constraint {constraint_name!r} in zone {zone_name!r} is {'missing' if not constraint_dirs else 'ambiguous'}")
        constraint = constraint_dirs[0]
        requested = finite_positive(entry.get("power_limit_w"), "power_limit_w", 1_000_000)
        limit_path = constraint / "power_limit_uw"
        if not limit_path.is_file() or not writable(limit_path):
            raise PowerError(f"RAPL power limit is missing or read-only: {limit_path}")
        lower = constraint / "min_power_uw"
        upper = constraint / "max_power_uw"
        if lower.is_file() and requested < int(read(lower)):
            raise PowerError(f"RAPL power limit {requested} is below hardware minimum {read(lower)}")
        if upper.is_file() and requested > int(read(upper)):
            raise PowerError(f"RAPL power limit {requested} exceeds hardware maximum {read(upper)}")
        time_path = constraint / "time_window_us"
        time_value = None
        if "time_window_s" in entry:
            time_value = finite_positive(entry["time_window_s"], "time_window_s", 1_000_000)
            if not time_path.is_file() or not writable(time_path):
                raise PowerError(f"RAPL time window is missing or read-only: {time_path}")
            lower = constraint / "min_time_window_us"
            upper = constraint / "max_time_window_us"
            if lower.is_file() and time_value < int(read(lower)):
                raise PowerError(f"RAPL time window {time_value} is below hardware minimum {read(lower)}")
            if upper.is_file() and time_value > int(read(upper)):
                raise PowerError(f"RAPL time window {time_value} exceeds hardware maximum {read(upper)}")
        plans.append((limit_path, str(requested)))
        if time_value is not None:
            plans.append((time_path, str(time_value)))
    return plans


def discover_control(root, relative, label, requested, choices=None):
    path = root / relative
    if not requested:
        return []
    if not path.is_file() or not writable(path):
        raise PowerError(f"Requested {label} is unsupported or read-only: {path}")
    if choices is not None:
        available = path.parent / "available_platform_profiles" if label == "platform profile" else path.parent / "scaling_available_governors"
        if available.is_file() and requested not in read(available).split():
            raise PowerError(f"Requested {label} {requested!r} is unavailable; choices: {read(available)}")
    return [(path, str(requested))]


def sysfs_plan(config, root):
    plans = []
    cpufreq = root / "devices/system/cpu/cpufreq"
    policies = sorted(path for path in cpufreq.glob("policy*") if path.is_dir())
    for policy in policies:
        if config.get("cpu_governor"):
            plans.extend(discover_control(policy, "scaling_governor", "CPU governor", config["cpu_governor"], True))
        if config.get("cpu_epp"):
            plans.extend(discover_control(policy, "energy_performance_preference", "CPU EPP", config["cpu_epp"]))
    if config.get("cpu_governor") and not policies:
        raise PowerError("Requested CPU governor but no cpufreq policy paths were found")
    if config.get("cpu_epp") and not policies:
        raise PowerError("Requested CPU EPP but no cpufreq policy paths were found")
    boost = config.get("cpu_boost")
    if boost is not None:
        if not isinstance(boost, bool):
            raise PowerError("cpu_boost must be true, false, or null")
        no_turbo = root / "devices/system/cpu/intel_pstate/no_turbo"
        cpufreq_boost = root / "devices/system/cpu/cpufreq/boost"
        if no_turbo.is_file():
            plans.extend(discover_control(root, "devices/system/cpu/intel_pstate/no_turbo", "CPU boost", "0" if boost else "1"))
        elif cpufreq_boost.is_file():
            plans.extend(discover_control(root, "devices/system/cpu/cpufreq/boost", "CPU boost", "1" if boost else "0"))
        else:
            raise PowerError("Requested CPU boost control is unsupported")
    profile = config.get("platform_profile", "")
    if profile:
        path = root / "firmware/acpi/platform_profile"
        plans.extend(discover_control(root, "firmware/acpi/platform_profile", "platform profile", profile, True))
        choices_path = path.parent / "platform_profile_choices"
        if choices_path.is_file() and profile not in read(choices_path).split():
            raise PowerError(f"Requested platform profile {profile!r} is unavailable; choices: {read(choices_path)}")
    plans.extend(validate_rapl(config.get("rapl_limits", []), root / "class/powercap"))
    return plans


def apply_plan(plans, check=False):
    report = []
    for item in plans:
        path, wanted = item[0], item[1]
        before = read(path)
        if not check and before != str(wanted):
            try:
                path.write_text(f"{wanted}\n")
            except OSError as error:
                raise PowerError(f"Cannot write {path}: {error}") from error
        effective = before if check or before == str(wanted) else read(path)
        report.append({"path": str(path), "requested": str(wanted), "effective": effective})
    return report


def apply(config, root=Path("/sys"), check=False, powerprofilesctl="/usr/bin/powerprofilesctl"):
    if config.get("backend") == "power-profiles-daemon":
        result = subprocess.run([powerprofilesctl, "get"], check=True, capture_output=True, text=True).stdout.strip()
        requested = config.get("profile", "balanced")
        if result != requested and not check:
            subprocess.run([powerprofilesctl, "set", requested], check=True)
            result = subprocess.run([powerprofilesctl, "get"], check=True, capture_output=True, text=True).stdout.strip()
        return [{"control": "profile", "requested": requested, "effective": result}]
    if config.get("backend") != "sysfs":
        raise PowerError("backend must be sysfs or power-profiles-daemon")
    return apply_plan(sysfs_plan(config, root), check)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--sysfs-root", type=Path, default=Path("/sys"))
    parser.add_argument("--check", action="store_true", help="validate and report without writing")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        print(json.dumps(apply(config, args.sysfs_root, args.check), indent=2, sort_keys=True))
    except (OSError, json.JSONDecodeError, PowerError, subprocess.CalledProcessError) as error:
        print(f"host-power: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
