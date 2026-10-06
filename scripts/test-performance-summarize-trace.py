#!/usr/bin/env python3
"""Deterministic regression checks for performance measurement semantics."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("summarizer", ROOT / "performance-summarize-trace.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def event(message, pid=42, timestamp="2026-10-06 12:00:01"):
    return f"{timestamp}.000 I Brev Test (2026-10-06)[{pid}:abcd] [eu.brevmail.brev:Performance] {message}\n"


class TraceTests(unittest.TestCase):
    def test_fetch_and_reload_are_not_visible_open_or_launch(self):
        buckets = MODULE.parse([
            event("ui.body.fetch finished surface=messageBody durationMs=0"),
            event("ui.list finished surface=messageList path=reload durationMs=30"),
            event("ui.startup.ready surface=workspace usableContent=true durationMs=70"),
        ] * 30)
        self.assertEqual(MODULE.budget_results(buckets, cached_workload=True), {})

    def test_process_and_run_filter_excludes_tests_and_prior_run(self):
        buckets = MODULE.parse([
            event("mail.messages.page finished path=cacheHit durationMs=1", pid=99),
            event("mail.messages.page finished path=cacheHit durationMs=2", timestamp="2026-10-06 11:59:00"),
            event("mail.messages.page finished path=cacheHit durationMs=150"),
        ], pid="42", start="2026-10-06 12:00:00")
        self.assertEqual(MODULE.pick(buckets, "mail.messages.page", path="cacheHit"), [150.0])

    def test_nearest_rank_and_sample_floor(self):
        self.assertEqual(MODULE.percentile(list(range(1, 21)), 95), 19)
        buckets = MODULE.parse([
            event(f"ui.body.visible surface=messageBody renderer=webView durationMs={value}")
            for value in range(1, 21)
        ] + [event("ui.body.visible failed surface=messageBody durationMs=9999")])
        self.assertEqual(MODULE.budget_results(buckets, cached_workload=True), {"cached_thread_open_ms": 19.0})
        self.assertEqual(MODULE.budget_results(buckets, cached_workload=False), {})
        sparse = MODULE.parse([event("ui.body.visible surface=messageBody durationMs=0")])
        self.assertEqual(MODULE.budget_results(sparse, cached_workload=True), {})
        self.assertTrue(MODULE.summarize([0])["limited_sample"])

    def test_startup_surfaces_and_usable_content_stay_separate(self):
        buckets = MODULE.parse([
            event("ui.startup.ready surface=sessionRestore usableContent=false durationMs=5"),
            event("ui.startup.ready surface=workspace usableContent=true durationMs=90"),
        ])
        self.assertEqual(len(buckets), 2)
        self.assertEqual(MODULE.budget_results(buckets, cached_workload=True), {})

    def test_cli_provenance_required_and_external_launch_explicit(self):
        with tempfile.TemporaryDirectory() as temp:
            trace = Path(temp) / "trace.log"
            records = "".join(event("ui.body.visible surface=messageBody durationMs=100") for _ in range(20))
            command = [sys.executable, str(ROOT / "performance-summarize-trace.py"), str(trace),
                       "--cached-workload", "--inbox-usable-ms", "750"]
            trace.write_text(records)
            unattributed = subprocess.run(command, capture_output=True, text=True, check=True)
            self.assertNotIn("cached_inbox_usable_ms", json.loads(unattributed.stdout))
            self.assertNotIn("cached_thread_open_ms", json.loads(unattributed.stdout))
            trace.write_text("# brev-performance pid=42 start=2026-10-06 12:00:00\n" + records)
            attributed = json.loads(subprocess.run(command, capture_output=True, text=True, check=True).stdout)
            self.assertEqual(attributed["cached_inbox_usable_ms"], 750)
            self.assertEqual(attributed["cached_thread_open_ms"], 100)
            invalid = subprocess.run(command + ["--memory-mb", "nan"], capture_output=True)
            self.assertNotEqual(invalid.returncode, 0)

    def test_collector_requires_bounded_pid_before_querying_logs(self):
        collector = str(ROOT / "collect-performance-trace.sh")
        for arguments in ([], ["--pid", "42"], ["--pid", "42 OR 1=1", "--start", "2026-10-06 12:00:00"]):
            self.assertEqual(subprocess.run(["bash", collector, *arguments], capture_output=True).returncode, 2)


if __name__ == "__main__":
    unittest.main()
