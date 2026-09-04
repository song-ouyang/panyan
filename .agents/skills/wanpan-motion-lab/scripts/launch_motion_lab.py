#!/usr/bin/env python3
"""Discover a safe mobile target and launch the Wanpan motion lab."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from typing import Any


DEFAULT_GRADES = "V1,V2,V3"
GRADE_SEQUENCE = re.compile(r"V(?:[0-9]|1[0-7])(?:,V(?:[0-9]|1[0-7]))*")
REPO_ROOT = Path(__file__).resolve().parents[4]
FLUTTER_APP = REPO_ROOT / "flutter_app"
LAB_TARGET = FLUTTER_APP / "tool" / "motion_preview_main.dart"


def parse_grades(raw: str) -> str:
    grades = [part.strip().upper() for part in raw.split(",")]
    normalized = ",".join(grades)
    if (
        len(grades) != 3
        or len(set(grades)) != 3
        or not GRADE_SEQUENCE.fullmatch(normalized)
    ):
        raise argparse.ArgumentTypeError(
            "grades must contain exactly 3 distinct comma-separated V0-V17 values, "
            "for example V2,V4,V5"
        )
    return normalized


def discover_devices() -> list[dict[str, Any]]:
    if shutil.which("flutter") is None:
        raise RuntimeError("flutter is not available on PATH")
    result = subprocess.run(
        ["flutter", "devices", "--machine"],
        cwd=FLUTTER_APP,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"flutter device discovery failed: {detail}")
    try:
        devices = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("flutter returned invalid device JSON") from error
    if not isinstance(devices, list):
        raise RuntimeError("flutter returned an unexpected device list")
    return [device for device in devices if isinstance(device, dict)]


def is_mobile(device: dict[str, Any]) -> bool:
    platform = str(device.get("targetPlatform", "")).lower()
    return platform.startswith("ios") or platform.startswith("android")


def is_supported_mobile(device: dict[str, Any]) -> bool:
    return bool(device.get("isSupported")) and is_mobile(device)


def sort_key(device: dict[str, Any]) -> tuple[int, str, str]:
    platform = str(device.get("targetPlatform", "")).lower()
    platform_priority = 0 if platform.startswith("ios") else 1
    return (
        platform_priority,
        str(device.get("name", "")).casefold(),
        str(device.get("id", "")),
    )


def print_devices(devices: list[dict[str, Any]]) -> None:
    mobile_devices = sorted((item for item in devices if is_mobile(item)), key=sort_key)
    if not mobile_devices:
        print("No iOS or Android device is currently available.")
        return
    print("Available iOS/Android devices:")
    for device in mobile_devices:
        kind = "simulator" if device.get("emulator") else "physical"
        support = "supported" if device.get("isSupported") else "unsupported"
        print(
            f"- {device.get('name', 'Unknown')} | {device.get('id', '?')} | "
            f"{device.get('targetPlatform', '?')} | {kind} | {support}"
        )


def choose_device(
    devices: list[dict[str, Any]], requested_id: str | None
) -> dict[str, Any]:
    supported = [device for device in devices if is_supported_mobile(device)]
    if requested_id:
        for device in supported:
            if device.get("id") == requested_id:
                return device
        raise RuntimeError(
            f"device '{requested_id}' is not an available supported iOS/Android target"
        )

    simulators = sorted(
        (device for device in supported if device.get("emulator")), key=sort_key
    )
    if simulators:
        return simulators[0]

    physical = sorted(
        (device for device in supported if not device.get("emulator")), key=sort_key
    )
    if len(physical) == 1:
        return physical[0]
    if len(physical) > 1:
        raise RuntimeError(
            "multiple physical devices are available; use --list and --device DEVICE_ID"
        )
    raise RuntimeError(
        "no supported iOS/Android device is available; start a simulator or connect a device"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Launch the debug-only Wanpan Flutter motion lab.",
    )
    parser.add_argument(
        "--list", action="store_true", help="list current iOS/Android targets and exit"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print the launch command without running it"
    )
    parser.add_argument("--device", metavar="DEVICE_ID", help="use this discovered device ID")
    parser.add_argument(
        "--grades",
        type=parse_grades,
        metavar="V1,V2,V3",
        help=f"configured milestone sequence (fallback: {DEFAULT_GRADES})",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if not FLUTTER_APP.is_dir() or not LAB_TARGET.is_file():
        print(
            "error: run the repository-local launcher from an intact Wanpan checkout",
            file=sys.stderr,
        )
        return 2

    try:
        devices = discover_devices()
        if args.list:
            print_devices(devices)
            return 0
        device = choose_device(devices, args.device)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    command = [
        "flutter",
        "run",
        "--debug",
        "-d",
        str(device["id"]),
        "-t",
        "tool/motion_preview_main.dart",
        "--dart-define=APP_ENV=development",
    ]
    effective_grades = args.grades or DEFAULT_GRADES
    if args.grades is not None:
        command.append(f"--dart-define=MOTION_MILESTONE_GRADES={args.grades}")
    print(
        f"Selected {device.get('name', 'Unknown')} ({device['id']}); "
        f"milestones: {effective_grades} "
        f"({'configured' if args.grades is not None else 'fallback'})",
        flush=True,
    )
    print(f"cwd: {FLUTTER_APP}", flush=True)
    print(f"command: {shlex.join(command)}", flush=True)
    if args.dry_run:
        return 0

    os.chdir(FLUTTER_APP)
    os.execvp(command[0], command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
