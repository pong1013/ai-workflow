"""Acceptance checks at the public validator CLI using real disposable Git state."""

import json
import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "skills/ai-workflow/references/state-machine.json"
VALIDATOR = ROOT / "scripts/validate_state_machine.py"


class DeliveryAcceptance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ai-workflow-delivery-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repository"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Acceptance Tests")
        self.git("config", "user.email", "tests@example.invalid")
        (self.root / "sample.txt").write_bytes(b"base\n")
        self.git("add", "sample.txt")
        self.git("commit", "-qm", "baseline")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.instance = {
            "workspaceBaseline": {"baseCommit": self.base, "entries": []},
            "mutationLedger": [], "setupReceiptImports": [], "approvedAlternatives": [],
            "delivery": {"configurationReconciled": True, "residualBaselineEntries": []},
        }

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True)

    def cli(self, *args):
        return subprocess.run(
            [sys.executable, str(VALIDATOR), str(MODEL), "--repository-root", str(self.root), *args],
            text=True, capture_output=True,
        )

    def view(self, action):
        args = ("--baseline", self.base) if action == "--emit-reconciliation-view" else ()
        result = self.cli(action, *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def delivery(self, passes=True):
        target = Path(self.temp.name) / "instance.json"
        target.write_text(json.dumps(self.instance))
        result = self.cli("--delivery", str(target))
        if passes:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("unrecognized arguments", result.stderr)
        return result

    def test_clean_repository_passes_delivery(self):
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.delivery()

    def capture_unrelated_baseline(self):
        current = self.view("--emit-reconciliation-view")
        pending = self.view("--emit-delivery-view")
        self.instance["workspaceBaseline"]["entries"] = current["entries"]
        self.instance["workspaceBaseline"]["pendingDiffHashes"] = pending["pendingDiffHashes"]
        self.instance["delivery"]["residualBaselineEntries"] = pending["entries"]
        return pending

    def test_exact_unrelated_staged_unstaged_and_untracked_baseline_passes(self):
        (self.root / "sample.txt").write_bytes(b"staged\n")
        self.git("add", "sample.txt")
        (self.root / "sample.txt").write_bytes(b"unstaged\n")
        (self.root / "personal.txt").write_bytes(b"unrelated\n")
        pending = self.capture_unrelated_baseline()
        self.assertEqual({entry["path"] for entry in pending["entries"]}, {"sample.txt", "personal.txt"})
        self.delivery()

    def test_delivery_requires_exact_residual_path_hunk_and_hash_disclosure(self):
        (self.root / "sample.txt").write_bytes(b"unrelated\n")
        self.capture_unrelated_baseline()
        original = self.instance["delivery"]["residualBaselineEntries"]
        for field, replacement in (("path", "other.txt"), ("hunk", "other-hunk"), ("contentHash", "sha256:" + "0" * 64)):
            with self.subTest(field=field):
                altered = [dict(entry) for entry in original]
                altered[0][field] = replacement
                self.instance["delivery"]["residualBaselineEntries"] = altered
                self.delivery(passes=False)
        self.instance["delivery"]["residualBaselineEntries"] = []
        self.delivery(passes=False)

    def test_changed_unrelated_baseline_blocks_delivery(self):
        (self.root / "sample.txt").write_bytes(b"unrelated\n")
        self.capture_unrelated_baseline()
        (self.root / "sample.txt").write_bytes(b"drift\n")
        self.delivery(passes=False)

    def test_dirty_baseline_requires_independent_pending_surface_hashes(self):
        (self.root / "sample.txt").write_bytes(b"unrelated\n")
        self.capture_unrelated_baseline()
        del self.instance["workspaceBaseline"]["pendingDiffHashes"]
        self.delivery(passes=False)

    def test_untracked_baseline_mode_drift_blocks_delivery(self):
        (self.root / "personal.txt").write_bytes(b"unrelated\n")
        self.capture_unrelated_baseline()
        (self.root / "personal.txt").chmod(0o755)
        self.delivery(passes=False)

    def test_transfer_between_index_and_worktree_is_baseline_drift(self):
        (self.root / "sample.txt").write_bytes(b"unrelated\n")
        self.capture_unrelated_baseline()
        self.git("add", "sample.txt")
        # The final durable diff is unchanged, but staging was never approved.
        self.delivery(passes=False)

    def test_net_zero_final_diff_does_not_mean_clean_index_and_worktree(self):
        (self.root / "sample.txt").write_bytes(b"staged\n")
        self.git("add", "sample.txt")
        (self.root / "sample.txt").write_bytes(b"base\n")
        self.assertEqual(self.git("diff", self.base), "")
        self.assertIn("MM sample.txt", self.git("status", "--porcelain"))
        self.delivery(passes=False)

    def test_clean_committed_ticket_requires_successful_reconciliation(self):
        (self.root / "sample.txt").write_bytes(b"ticket\n")
        entry, = self.view("--emit-reconciliation-view")["entries"]
        self.instance["mutationLedger"] = [{
            "sequence": 1, "stage": "ticket-work", "ticket": "#13", "provenance": "ticket-owned",
            "path": entry["path"], "hunk": entry["hunk"],
            "beforeHash": entry["beforeHash"], "afterHash": entry["afterHash"],
        }]
        self.git("add", "sample.txt")
        self.git("commit", "-qm", "verified ticket")
        self.delivery()
        self.instance["mutationLedger"] = []
        self.delivery(passes=False)

    def test_reconciliation_flag_does_not_authorize_uncommitted_ticket_output(self):
        (self.root / "sample.txt").write_bytes(b"ticket\n")
        entry, = self.view("--emit-reconciliation-view")["entries"]
        self.instance["mutationLedger"] = [{
            "sequence": 1, "stage": "ticket-work", "ticket": "#13", "provenance": "ticket-owned",
            "path": entry["path"], "hunk": entry["hunk"],
            "beforeHash": entry["beforeHash"], "afterHash": entry["afterHash"],
        }]
        self.delivery(passes=False)

    def test_approved_deferral_requires_standalone_exact_evidence_and_later_workspace_gate(self):
        draft = {
            "state": "exception", "authority": "exception", "approvalReference": "current-task-user-message-42",
            "artifact": "standalone-github-issue", "inParentChildGraph": False,
            "automaticPostMergeBranch": False, "laterRun": "origin-pr-merged-and-new-workspace-gate",
            "originatingFeature": "pong1013/ai-workflow#10", "reason": "defer configuration to separately approved scope",
            "mutations": [{"path": "docs/agents/domain.md", "hunk": "@@ -1 +1 @@",
                           "contentHash": "sha256:" + "1" * 64, "provenance": "project knowledge"}],
        }
        target = Path(self.temp.name) / "follow-up.json"

        def validate(value, passes):
            target.write_text(json.dumps(value))
            result = subprocess.run(
                [sys.executable, str(VALIDATOR), str(MODEL), "--deferred-follow-up", str(target)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode == 0, passes, result.stdout + result.stderr)
            self.assertNotIn("unrecognized arguments", result.stderr)

        validate(draft, True)
        for field, replacement in (("authority", "delivery"), ("approvalReference", ""),
                                   ("artifact", "child-ticket"), ("inParentChildGraph", True),
                                   ("automaticPostMergeBranch", True), ("laterRun", "automatic"),
                                   ("originatingFeature", ""), ("reason", ""), ("mutations", [])):
            with self.subTest(field=field):
                altered = copy.deepcopy(draft)
                altered[field] = replacement
                validate(altered, False)
        for field in ("path", "hunk", "contentHash", "provenance"):
            with self.subTest(evidence_field=field):
                altered = copy.deepcopy(draft)
                del altered["mutations"][0][field]
                validate(altered, False)

    def test_state_model_rejects_new_residual_gate_and_automatic_deferred_branch(self):
        original = json.loads(MODEL.read_text())
        for section, field, replacement in (
            ("deliveryPolicy", "residualApproval", "new-residual-gate"),
            ("deliveryPolicy", "requiresReconciliation", False),
            ("deferredFollowUp", "automaticPostMergeBranch", True),
            ("deferredFollowUp", "inParentChildGraph", True),
        ):
            with self.subTest(field=field):
                altered = copy.deepcopy(original)
                policy = altered["deliveryPolicy"]
                if section == "deferredFollowUp":
                    policy = policy["deferredFollowUp"]
                policy[field] = replacement
                target = Path(self.temp.name) / "model.json"
                target.write_text(json.dumps(altered))
                result = subprocess.run([sys.executable, str(VALIDATOR), str(target)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
