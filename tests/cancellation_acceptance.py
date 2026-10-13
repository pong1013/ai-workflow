"""Canceled action histories are retained and bound through the public Git CLI seam."""

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "skills/ai-workflow/references/state-machine.json"
VALIDATOR = ROOT / "scripts/validate_state_machine.py"


class CancellationAcceptance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ai-workflow-cancellation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repository"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Acceptance Tests")
        self.git("config", "user.email", "tests@example.invalid")
        self.git("config", "core.filemode", "true")
        self.sample = self.root / "sample.txt"
        self.sample.write_bytes(b"A\n")
        self.commit("baseline")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.instance = {
            "workspaceBaseline": {"baseCommit": self.base, "entries": []},
            "mutationLedger": [], "setupReceiptImports": [], "approvedAlternatives": [],
        }

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def cli(self, *args):
        return subprocess.run(
            [sys.executable, str(VALIDATOR), str(MODEL), "--repository-root", str(self.root), *args],
            text=True, capture_output=True,
        )

    def capture(self, baseline):
        result = self.cli("--baseline", baseline, "--emit-reconciliation-view")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)["entries"]

    def record(self, entries):
        for entry in entries:
            self.instance["mutationLedger"].append({
                "sequence": len(self.instance["mutationLedger"]) + 1,
                "stage": "ticket-work", "ticket": "#12", "provenance": "ticket-owned",
                **{field: entry[field] for field in ("path", "hunk", "beforeHash", "afterHash")},
            })

    def validate(self, passes=True, delivery=False):
        target = Path(self.temp.name) / "instance.json"
        target.write_text(json.dumps(self.instance))
        before = target.read_bytes()
        if delivery:
            self.instance["delivery"] = {"configurationReconciled": True, "residualBaselineEntries": []}
            target.write_text(json.dumps(self.instance))
            before = target.read_bytes()
        result = self.cli("--delivery" if delivery else "--reconciliation", str(target))
        if passes:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("unrecognized arguments", result.stderr)
        self.assertEqual(target.read_bytes(), before, "validation must preserve append-only history")
        return result

    def round_trip(self, intermediate=b"B\n", retain_identity=False):
        original = self.sample.read_bytes()
        self.sample.write_bytes(intermediate)
        forward = self.capture(self.base)
        self.record(forward)
        self.commit("first meaningful action")
        middle = self.git("rev-parse", "HEAD").strip()
        self.sample.write_bytes(original)
        reverse = self.capture(middle)
        if retain_identity:
            self.assertEqual(len(forward), 1)
            self.assertEqual(len(reverse), 1)
            # The inverse action uses the original historical hunk identity;
            # both side hashes still come from its own real Git patch.
            reverse[0]["hunk"] = forward[0]["hunk"]
        self.record(reverse)
        self.commit("second meaningful action")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.capture(self.base), [])
        return forward, reverse

    def test_canceled_text_actions_pass_without_erasing_history(self):
        forward, reverse = self.round_trip()
        self.assertEqual(forward[0]["hunk"], "@@ -1 +1 @@")
        self.assertEqual(reverse[0]["hunk"], forward[0]["hunk"])
        self.assertEqual(forward[0]["beforeHash"], "sha256:" + hashlib.sha256(b"A\n").hexdigest())
        self.assertEqual(reverse[0]["afterHash"], forward[0]["beforeHash"])
        self.validate()
        self.validate(delivery=True)
        self.assertEqual(len(self.instance["mutationLedger"]), 2)

    def test_canceled_text_with_embedded_cr_uses_exact_raw_bytes(self):
        self.sample.write_bytes(b"A\rhidden\n")
        self.commit("raw byte baseline")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.instance["workspaceBaseline"]["baseCommit"] = self.base
        self.round_trip(b"B\rhidden\n")
        self.validate()

    def test_wrong_initial_hash_is_rejected_even_when_terminal_is_base(self):
        self.round_trip()
        self.instance["mutationLedger"][0]["beforeHash"] = "sha256:" + hashlib.sha256(b"forged\n").hexdigest()
        self.validate(passes=False)

    def test_equal_forged_endpoints_are_not_baseline_proof(self):
        self.round_trip()
        forged = "sha256:" + hashlib.sha256(b"forged\n").hexdigest()
        self.instance["mutationLedger"][0]["beforeHash"] = forged
        self.instance["mutationLedger"][-1]["afterHash"] = forged
        self.validate(passes=False)

    def test_wrong_terminal_hash_is_rejected(self):
        self.round_trip()
        self.instance["mutationLedger"][-1]["afterHash"] = "sha256:" + hashlib.sha256(b"other\n").hexdigest()
        self.validate(passes=False)

    def test_unknown_and_out_of_range_hunks_are_rejected(self):
        self.round_trip()
        original = copy.deepcopy(self.instance)
        for hunk in ("unknown-hunk", "@@ -99 +99 @@"):
            with self.subTest(hunk=hunk):
                self.instance = copy.deepcopy(original)
                for event in self.instance["mutationLedger"]:
                    event["hunk"] = hunk
                self.validate(passes=False)

    def test_live_drift_after_cancel_blocks_reconciliation(self):
        self.round_trip()
        self.sample.write_bytes(b"drift\n")
        self.validate(passes=False)

    def test_broken_canceled_chain_is_rejected(self):
        self.round_trip()
        self.instance["mutationLedger"][1]["beforeHash"] = "sha256:" + hashlib.sha256(b"not B\n").hexdigest()
        self.validate(passes=False)

    def test_canceled_binary_actions_pass(self):
        self.sample.write_bytes(b"A\0raw\n")
        self.commit("binary baseline")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.instance["workspaceBaseline"]["baseCommit"] = self.base
        forward, reverse = self.round_trip(b"B\0raw\n")
        self.assertEqual(forward[0]["hunk"], "whole-file")
        self.assertEqual(reverse[0]["hunk"], "whole-file")
        self.validate()

    def test_canceled_mode_actions_pass(self):
        self.sample.chmod(0o755)
        self.record(self.capture(self.base))
        self.commit("make executable")
        middle = self.git("rev-parse", "HEAD").strip()
        self.sample.chmod(0o644)
        self.record(self.capture(middle))
        self.commit("restore mode")
        self.assertEqual(self.capture(self.base), [])
        self.validate()

    def test_untracked_create_delete_retains_history(self):
        new_file = self.root / "temporary.txt"
        new_file.write_bytes(b"temporary\n")
        entry, = self.capture(self.base)
        self.assertEqual(entry["hunk"], "whole-file")
        self.record([entry])
        new_file.unlink()
        self.record([{**entry, "beforeHash": entry["afterHash"], "afterHash": entry["beforeHash"]}])
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.validate()

    def test_dirty_index_after_cancel_still_blocks_delivery(self):
        self.round_trip()
        self.sample.write_bytes(b"B\n")
        self.git("add", "sample.txt")
        self.sample.write_bytes(b"A\n")
        self.assertEqual(self.capture(self.base), [])
        self.assertIn("MM sample.txt", self.git("status", "--porcelain"))
        self.validate(passes=False, delivery=True)

    def test_canceled_hunk_coexists_with_accounted_distant_live_hunk(self):
        original = b"".join(f"line {number}\n".encode() for number in range(1, 11))
        self.sample.write_bytes(original)
        self.commit("multiline baseline")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.instance["workspaceBaseline"]["baseCommit"] = self.base
        self.round_trip(original.replace(b"line 2\n", b"temporary 2\n"))
        self.sample.write_bytes(original.replace(b"line 9\n", b"final 9\n"))
        self.record(self.capture(self.base))
        self.validate()

    def test_count_changing_cancellation_passes_when_whole_file_is_restored(self):
        self.round_trip(b"B\nextra\n", retain_identity=True)
        self.validate()

    def test_insert_then_remove_text_passes_with_original_hunk_identity(self):
        self.round_trip(b"A\ninserted\n", retain_identity=True)
        self.validate()

    def test_delete_then_restore_text_passes_with_original_hunk_identity(self):
        self.round_trip(b"", retain_identity=True)
        self.validate()

    def test_count_changing_cancellation_with_distant_live_change_is_ambiguous(self):
        original = b"".join(f"line {number}\n".encode() for number in range(1, 11))
        self.sample.write_bytes(original)
        self.commit("multiline baseline")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.instance["workspaceBaseline"]["baseCommit"] = self.base
        self.round_trip(original.replace(b"line 2\n", b"line 2\ninserted\n"), retain_identity=True)
        self.sample.write_bytes(original.replace(b"line 9\n", b"final 9\n"))
        self.record(self.capture(self.base))
        self.validate(passes=False)

    def test_disappearing_unrelated_baseline_hunk_is_not_clean_cancellation(self):
        self.sample.write_bytes(b"unrelated\n")
        entry, = self.capture(self.base)
        self.instance["workspaceBaseline"]["entries"] = [entry]
        self.sample.write_bytes(b"A\n")
        self.record([{**entry, "beforeHash": entry["afterHash"], "afterHash": entry["beforeHash"]}])
        self.assertEqual(self.capture(self.base), [])
        self.validate(passes=False)


if __name__ == "__main__":
    unittest.main()
