#!/usr/bin/env python3
"""Pure tests: no Xcode, simulator, account or network access."""
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location(
    "snapshot_environment", Path(__file__).with_name("settings-snapshot-environment.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SnapshotEnvironmentTests(unittest.TestCase):
    def inputs(self):
        return dict(
            xcode="Xcode 26.6\nBuild version 17F113\n",
            sdk_version="26.5",
            sdk_build="23F81a",
            runtimes={"runtimes": [{
                "version": "26.5", "buildversion": "23F77", "isAvailable": True,
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            }]},
            devices={"devicetypes": [{
                "name": "iPhone 16e",
                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16e",
            }]},
        )

    def test_exact_profile(self):
        result = module.validate(**self.inputs())
        self.assertEqual(result["runtime_build"], "23F77")
        self.assertEqual(result["renderer"], "scene-hierarchy-v1")
        self.assertFalse(result["diagnostic"])

    def test_wrong_xcode_or_sdk(self):
        for key, value in [
            ("xcode", "Xcode 27.0\nBuild version 18A1"),
            ("xcode", "Xcode 26.6\nBuild version 17F999"),
            ("sdk_version", "27.0"), ("sdk_build", "23F99"),
        ]:
            with self.subTest(key=key, value=value):
                inputs = self.inputs()
                inputs[key] = value
                with self.assertRaises(ValueError):
                    module.validate(**inputs)

    def test_runtime_mismatch_missing_unavailable_or_ambiguous(self):
        for variant in ("version", "buildversion", "unavailable", "missing", "duplicate"):
            inputs = self.inputs()
            runtime = inputs["runtimes"]["runtimes"][0]
            if variant in ("version", "buildversion"):
                runtime[variant] = "wrong"
            elif variant == "unavailable":
                runtime["isAvailable"] = False
            elif variant == "missing":
                inputs["runtimes"]["runtimes"] = []
            else:
                inputs["runtimes"]["runtimes"].append(runtime.copy())
            with self.subTest(variant=variant), self.assertRaises(ValueError):
                module.validate(**inputs)

    def test_device_is_not_silently_substituted(self):
        inputs = self.inputs()
        inputs["devices"]["devicetypes"][0]["name"] = "iPhone 17 Pro"
        with self.assertRaises(ValueError):
            module.validate(**inputs)

    def test_explicit_local_diagnostic_is_labeled(self):
        inputs = self.inputs()
        inputs["runtimes"]["runtimes"][0]["buildversion"] = "23F73"
        result = module.validate(**inputs, diagnostic_runtime_build="23F73")
        self.assertTrue(result["diagnostic"])
        self.assertEqual(result["runtime_build"], "23F73")

    def test_ci_cannot_override_runtime(self):
        with self.assertRaises(ValueError):
            module.validate(**self.inputs(), diagnostic_runtime_build="23F73", ci=True)


if __name__ == "__main__":
    unittest.main()
