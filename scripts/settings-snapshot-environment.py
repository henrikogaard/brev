#!/usr/bin/env python3
"""Validate the dedicated iOS Settings capture profile before building/launching."""
import argparse
import json
import os
import subprocess
import sys


def validate(*, xcode, sdk_version, sdk_build, runtimes, devices,
             diagnostic_runtime_build=None, ci=False):
    if diagnostic_runtime_build and ci:
        raise ValueError("CI cannot override the pinned runtime build")
    if xcode.splitlines() != ["Xcode 26.6", "Build version 17F113"]:
        raise ValueError("Settings snapshots require Xcode 26.6 / 17F113")
    if sdk_version.strip() != "26.5" or sdk_build.strip() != "23F81a":
        raise ValueError("Settings snapshots require simulator SDK 26.5 / 23F81a")
    build = diagnostic_runtime_build or "23F77"
    matches = [
        runtime for runtime in runtimes["runtimes"]
        if runtime.get("version") == "26.5"
        and runtime.get("buildversion") == build
        and runtime.get("isAvailable") is True
    ]
    if len(matches) != 1:
        raise ValueError(f"Exactly one available iOS 26.5 / {build} runtime is required")
    types = [
        device for device in devices["devicetypes"]
        if device.get("name") == "iPhone 16e"
        and device.get("identifier") == "com.apple.CoreSimulator.SimDeviceType.iPhone-16e"
    ]
    if len(types) != 1:
        raise ValueError("The pinned iPhone 16e device type is unavailable or ambiguous")
    return {
        "xcode": "26.6", "xcode_build": "17F113",
        "sdk": "26.5", "sdk_build": "23F81a",
        "runtime": "26.5", "runtime_build": build,
        "runtime_identifier": matches[0]["identifier"],
        "device": "iPhone 16e", "device_identifier": types[0]["identifier"],
        "renderer": "scene-hierarchy-v1",
        "snapshot_testing": "1.19.7",
        "content_scale": 2, "width_points": 375,
        "heights_points": [812, 1800],
        "language": "en", "region": "en_US",
        "horizontal_size_class": "compact",
        "variants": ["light-large", "dark-large", "light-accessibility3"],
        "diagnostic": bool(diagnostic_runtime_build),
    }


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnostic-runtime-build",
                        help="Explicit local-only deviation; never CI/reference acceptance")
    args = parser.parse_args()
    try:
        profile = validate(
            xcode=output("xcodebuild", "-version"),
            sdk_version=output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"),
            sdk_build=output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-build-version"),
            runtimes=json.loads(output("xcrun", "simctl", "list", "runtimes", "available", "--json")),
            devices=json.loads(output("xcrun", "simctl", "list", "devicetypes", "--json")),
            diagnostic_runtime_build=args.diagnostic_runtime_build,
            ci=os.environ.get("CI", "").lower() in ("true", "1"),
        )
        profile["developer_dir"] = os.environ.get("DEVELOPER_DIR") or output("xcode-select", "-p")
        print(json.dumps(profile, indent=2, sort_keys=True))
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Settings snapshot preflight failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
