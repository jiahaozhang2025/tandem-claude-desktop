import importlib.util
import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "session-handoff.py"
SPEC = importlib.util.spec_from_file_location("session_handoff", MODULE_PATH)
h = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = h
SPEC.loader.exec_module(h)


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "profiles"
        self.root.mkdir()
        self.profiles = {}
        for name in ("main", "account2"):
            data, code = self.base / name / "data", self.base / name / "code"
            data.mkdir(parents=True)
            code.mkdir()
            account, org = str(uuid.uuid4()), str(uuid.uuid4())
            self.write_json(data / "config.json", {"lastKnownAccountUuid": account, "auth": "keep-" + name})
            self.write_json(code / ".claude.json", {"oauthAccount": {"accountUuid": account, "organizationUuid": org}})
            (code / ".credentials.json").write_text("private-" + name)
            self.profiles[name] = h.Profile(name, data, code)
        self.sid, self.cid = "local_" + str(uuid.uuid4()), str(uuid.uuid4())
        self.record = {
            "sessionId": self.sid, "cliSessionId": self.cid, "cwd": "C:\\project",
            "title": "A conversation", "lastActivityAt": 100, "completedTurns": 1,
            "permissionMode": "auto", "remoteMcpServersConfig": {"token": "do-not-copy"},
            "bridgeSessionIds": ["private-bridge"], "sshRemoteProcessId": "private-process-handle",
        }
        self.write_json(self.profiles["main"].scope() / (self.sid + ".json"), self.record)
        self.rel = Path("C--project") / (self.cid + ".jsonl")
        self.transcript = self.profiles["main"].code / "projects" / self.rel
        self.transcript.parent.mkdir(parents=True)
        self.transcript.write_text('{"type":"user","message":{"content":"hello"}}\n')

    @staticmethod
    def write_json(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def execute(self, target):
        return h.execute(self.root, self.profiles, target)

    def test_preview_is_read_only(self):
        result = h.summary(h.prepare(self.root, self.profiles, "account2"))
        self.assertEqual(result["sessions"], 1)
        self.assertFalse((self.root / "session-store").exists())
        self.assertFalse((self.root / "handoff-state.json").exists())

    def test_handoff_preserves_session_ids_transcript_and_folder(self):
        result = self.execute("account2")
        destination = self.profiles["account2"]
        record = h.read_json(destination.scope() / (self.sid + ".json"))
        self.assertEqual(record["sessionId"], self.sid)
        self.assertEqual(record["cliSessionId"], self.cid)
        self.assertEqual(record["cwd"], self.record["cwd"])
        self.assertEqual((destination.code / "projects" / self.rel).read_bytes(), self.transcript.read_bytes())
        self.assertEqual(result["sessions"], 1)

    def test_preflight_is_read_only(self):
        before = {p: p.read_bytes() for p in self.base.rglob("*") if p.is_file()}
        h.validate_plan(h.prepare(self.root, self.profiles, "account2"))
        self.assertEqual(before, {p: p.read_bytes() for p in self.base.rglob("*") if p.is_file()})

    def test_preflight_rejects_independent_destination_edits_without_writes(self):
        self.execute("account2")
        self.execute("main")
        destination = self.profiles["account2"].code / "projects" / self.rel
        with destination.open("a") as stream:
            stream.write('{"type":"user","message":{"content":"independent edit"}}\n')
        before = {p: p.read_bytes() for p in self.base.rglob("*") if p.is_file()}
        with self.assertRaisesRegex(h.HandoffError, "Destination history changed"):
            h.validate_plan(h.prepare(self.root, self.profiles, "account2"))
        self.assertEqual(before, {p: p.read_bytes() for p in self.base.rglob("*") if p.is_file()})

    def test_preflight_rejects_remote_mid_turn(self):
        record = dict(self.record, sshConfig={"host": "example.test"}, sshReattach={"midTurn": True})
        self.write_json(self.profiles["main"].scope() / (self.sid + ".json"), record)
        with self.assertRaisesRegex(h.HandoffError, "mid-turn"):
            h.validate_plan(h.prepare(self.root, self.profiles, "account2"))
        self.assertFalse((self.root / "handoff.lock").exists())

    def test_credentials_and_prior_permissions_do_not_travel(self):
        self.execute("account2")
        target = self.profiles["account2"]
        self.assertEqual((target.code / ".credentials.json").read_text(), "private-account2")
        self.assertEqual(h.read_json(target.data / "config.json")["auth"], "keep-account2")
        record = h.read_json(target.scope() / (self.sid + ".json"))
        self.assertEqual(record["permissionMode"], "default")
        for key in ("remoteMcpServersConfig", "bridgeSessionIds", "sshRemoteProcessId"):
            self.assertNotIn(key, record)

    def test_new_turn_survives_switching_back(self):
        self.execute("account2")
        target = self.profiles["account2"]
        transcript = target.code / "projects" / self.rel
        with transcript.open("a") as stream:
            stream.write('{"type":"assistant","message":{"content":"continued"}}\n')
        changed = dict(self.record, lastActivityAt=200)
        self.write_json(target.scope() / (self.sid + ".json"), changed)
        self.execute("main")
        self.assertEqual(self.transcript.read_bytes(), transcript.read_bytes())
        self.assertEqual(h.read_json(self.profiles["main"].scope() / (self.sid + ".json"))["lastActivityAt"], 200)

    def add_session_outside_last_owner(self, remote=False):
        sid, cid = "local_" + str(uuid.uuid4()), str(uuid.uuid4())
        record = dict(self.record, sessionId=sid, cliSessionId=cid, title="New session outside launcher", lastActivityAt=200)
        if remote:
            record.update(sshConfig={"sshHost": "example"}, sshReattach={"midTurn": False})
        self.write_json(self.profiles["main"].scope() / (sid + ".json"), record)
        folder = "ssh-" + cid if remote else "C--project"
        transcript = self.profiles["main"].code / "projects" / folder / (cid + ".jsonl")
        transcript.parent.mkdir(parents=True, exist_ok=True)
        transcript.write_text('{"type":"user","message":{"content":"new conversation"}}\n')
        return record, transcript

    def test_new_session_in_inactive_profile_is_discovered_and_transferred(self):
        self.execute("account2")
        record, transcript = self.add_session_outside_last_owner()
        self.assertEqual(h.pending_new_sessions(self.root, self.profiles), 1)
        self.assertFalse((self.root / "session-store" / "records" / (record["sessionId"] + ".json")).exists())
        result = self.execute("account2")
        self.assertEqual(result["sessions"], 2)
        destination = self.profiles["account2"]
        self.assertEqual(h.read_json(destination.scope() / (record["sessionId"] + ".json"))["cliSessionId"], record["cliSessionId"])
        rel = transcript.relative_to(self.profiles["main"].code / "projects")
        self.assertEqual((destination.code / "projects" / rel).read_bytes(), transcript.read_bytes())
        self.assertEqual(h.pending_new_sessions(self.root, self.profiles), 0)
        self.assertEqual((destination.code / ".credentials.json").read_text(), "private-account2")

    def test_new_ssh_cache_and_sidecars_are_imported_without_stale_reattach(self):
        self.execute("account2")
        record, transcript = self.add_session_outside_last_owner(remote=True)
        sidecar = transcript.parent / ".owner"
        sidecar.write_text("synthetic-cache-owner")
        result = self.execute("account2")
        self.assertEqual(result["sshSessions"], 1)
        destination = self.profiles["account2"]
        copied = h.read_json(destination.scope() / (record["sessionId"] + ".json"))
        self.assertNotIn("sshReattach", copied)
        self.assertEqual(copied["sshConfig"], record["sshConfig"])
        rel = sidecar.relative_to(self.profiles["main"].code / "projects")
        self.assertEqual((destination.code / "projects" / rel).read_bytes(), sidecar.read_bytes())

    def test_inactive_existing_edits_are_not_imported_with_a_new_session(self):
        self.execute("account2")
        self.add_session_outside_last_owner()
        self.transcript.write_text('{"type":"user","message":{"content":"inactive edit"}}\n')
        original = (self.profiles["account2"].code / "projects" / self.rel).read_bytes()
        self.execute("account2")
        self.assertEqual((self.profiles["account2"].code / "projects" / self.rel).read_bytes(), original)
        self.assertNotEqual(self.transcript.read_bytes(), original)

    def test_new_session_with_conflicting_existing_transcript_is_refused(self):
        self.execute("account2")
        record = dict(self.record, sessionId="local_" + str(uuid.uuid4()))
        self.write_json(self.profiles["main"].scope() / (record["sessionId"] + ".json"), record)
        self.transcript.write_text('{"type":"user","message":{"content":"conflicting"}}\n')
        with self.assertRaisesRegex(h.HandoffError, "newly discovered session conflicts"):
            self.execute("account2")
        self.assertFalse((self.profiles["account2"].scope() / (record["sessionId"] + ".json")).exists())

    def test_new_inactive_remote_mid_turn_still_blocks_transfer(self):
        self.execute("account2")
        record, _ = self.add_session_outside_last_owner(remote=True)
        record["sshReattach"]["midTurn"] = True
        self.write_json(self.profiles["main"].scope() / (record["sessionId"] + ".json"), record)
        with self.assertRaisesRegex(h.HandoffError, "mid-turn"):
            self.execute("account2")

    def test_previously_reported_missing_session_does_not_force_activation_sync(self):
        self.execute("account2")
        record, transcript = self.add_session_outside_last_owner()
        transcript.unlink()
        self.assertEqual(h.pending_new_sessions(self.root, self.profiles), 1)
        result = self.execute("account2")
        self.assertIn(record["sessionId"], [r["sessionId"] for r in result["unavailable"]])
        self.assertEqual(h.pending_new_sessions(self.root, self.profiles), 0)

    def test_missing_transcript_is_reported_not_invented(self):
        missing = dict(self.record, sessionId="local_" + str(uuid.uuid4()), cliSessionId=str(uuid.uuid4()))
        self.write_json(self.profiles["main"].scope() / (missing["sessionId"] + ".json"), missing)
        result = self.execute("account2")
        self.assertEqual(result["unavailable"][0]["sessionId"], missing["sessionId"])
        self.assertFalse((self.profiles["account2"].scope() / (missing["sessionId"] + ".json")).exists())
        self.assertTrue((self.profiles["main"].scope() / (missing["sessionId"] + ".json")).exists())

    def test_skipped_history_stays_visible_in_later_reports(self):
        missing = dict(self.record, sessionId="local_" + str(uuid.uuid4()), cliSessionId=str(uuid.uuid4()))
        self.write_json(self.profiles["main"].scope() / (missing["sessionId"] + ".json"), missing)
        self.execute("account2")
        self.assertEqual(len(self.execute("main")["unavailable"]), 1)

    def test_divergent_conversations_are_not_overwritten(self):
        self.execute("account2")
        destination = self.profiles["account2"].code / "projects" / self.rel
        destination.write_text('{"type":"user","message":{"content":"different"}}\n')
        original = self.transcript.read_bytes()
        with self.assertRaisesRegex(h.HandoffError, "Divergent"):
            self.execute("main")
        self.assertEqual(self.transcript.read_bytes(), original)

    def test_active_rewind_is_not_silently_replaced_by_old_history(self):
        first_line = self.transcript.read_bytes()
        with self.transcript.open("a") as stream:
            stream.write('{"type":"assistant","message":{"content":"second turn"}}\n')
        self.execute("account2")
        target = self.profiles["account2"].code / "projects" / self.rel
        target.write_bytes(first_line)
        with self.assertRaisesRegex(h.HandoffError, "rewound or truncated"):
            self.execute("main")
        self.assertEqual(target.read_bytes(), first_line)
        self.assertEqual(h.read_json(self.root / "handoff-state.json")["owner"], "account2")

    def test_partial_json_line_blocks_handoff(self):
        with self.transcript.open("a") as stream:
            stream.write('{"type":')
        with self.assertRaisesRegex(h.HandoffError, "No complete"):
            self.execute("account2")
        self.assertFalse((self.root / "handoff-state.json").exists())

    def test_transaction_rolls_back_after_publish_failure(self):
        original = h.Transaction.write
        def fail_on_metadata(tx, destination, **kwargs):
            if destination == self.profiles["account2"].scope() / (self.sid + ".json"):
                raise OSError("injected disk failure")
            return original(tx, destination, **kwargs)
        with patch.object(h.Transaction, "write", fail_on_metadata):
            with self.assertRaisesRegex(OSError, "injected"):
                self.execute("account2")
        self.assertFalse((self.profiles["account2"].code / "projects" / self.rel).exists())
        self.assertFalse((self.root / "handoff-state.json").exists())
        self.assertTrue(self.transcript.exists())
        self.assertFalse((self.root / "handoff.lock").exists())

    def test_lock_prevents_two_handoffs(self):
        (self.root / "handoff.lock").write_text("locked")
        with self.assertRaisesRegex(h.HandoffError, "lock"):
            self.execute("account2")

    def test_missing_account_does_not_guess(self):
        self.write_json(self.profiles["account2"].data / "config.json", {})
        with self.assertRaisesRegex(h.HandoffError, "Sign in"):
            self.execute("account2")

    def test_ambiguous_organization_does_not_guess(self):
        target = self.profiles["account2"]
        account = h.read_json(target.data / "config.json")["lastKnownAccountUuid"]
        self.write_json(target.code / ".claude.json", {})
        for _ in range(2):
            (target.data / "claude-code-sessions" / account / str(uuid.uuid4())).mkdir(parents=True)
        with self.assertRaisesRegex(h.HandoffError, "organization"):
            self.execute("account2")

    def test_remote_mid_turn_blocks_without_killing_processes(self):
        remote = dict(self.record, sshConfig={"sshHost": "example"}, sshReattach={"midTurn": True})
        self.write_json(self.profiles["main"].scope() / (self.sid + ".json"), remote)
        with self.assertRaisesRegex(h.HandoffError, "mid-turn"):
            self.execute("account2")
        self.assertFalse((self.root / "session-store").exists())

    def test_ssh_handles_are_never_treated_as_os_pids(self):
        remote = dict(self.record, sshConfig={"sshHost": "example"}, sshRemoteProcessId=str(uuid.uuid4()))
        self.write_json(self.profiles["main"].scope() / (self.sid + ".json"), remote)
        result = self.execute("account2")
        self.assertEqual(result["sshSessions"], 1)
        self.assertFalse(result["sshWorkerStateVerified"])

    def test_history_sidecars_are_preserved(self):
        sidecar = self.transcript.parent / self.cid / "subagents" / "agent-test.jsonl"
        sidecar.parent.mkdir(parents=True)
        sidecar.write_text('{"type":"assistant"}\n')
        self.execute("account2")
        target = self.profiles["account2"].code / "projects" / sidecar.relative_to(self.profiles["main"].code / "projects")
        self.assertEqual(target.read_bytes(), sidecar.read_bytes())

    def test_backups_keep_overwritten_destination(self):
        destination = self.profiles["account2"].code / "projects" / self.rel
        destination.parent.mkdir(parents=True)
        destination.write_bytes(self.transcript.read_bytes())
        original = destination.read_bytes()
        with self.transcript.open("a") as stream:
            stream.write('{"type":"assistant"}\n')
        result = self.execute("account2")
        backups = list(Path(result["backup"]).glob("*.bak"))
        self.assertTrue(any(p.read_bytes() == original for p in backups))


if __name__ == "__main__":
    unittest.main()
