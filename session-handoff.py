"""Sequential local-history handoff. Standard library only; never copies credentials."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)
SESSION = re.compile(r"^local_[0-9a-f-]{36}$", re.I)
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
# Account grants, connector configuration, bridge tokens, process handles and
# prior permission approvals deliberately do not travel between accounts.
RECORD_FIELDS = {
    "sessionId", "cliSessionId", "cwd", "originCwd", "createdAt", "lastActivityAt",
    "model", "effort", "isArchived", "title", "titleSource", "completedTurns",
    "sshConfig", "wslConfig", "sshRemoteTranscriptPath", "userSelectedFolders",
}


class HandoffError(Exception):
    pass


def read_json(path: Path, default=None):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (ValueError, OSError) as exc:
        raise HandoffError(f"Cannot read JSON: {path}") from exc


def safe_path(path: Path):
    """Reject links before resolving, including Windows junctions."""
    absolute = Path(os.path.abspath(path))
    for item in (absolute, *absolute.parents):
        try:
            stat = item.lstat()
        except FileNotFoundError:
            continue
        if item.is_symlink() or getattr(stat, "st_file_attributes", 0) & 0x400:
            raise HandoffError(f"Linked history path is unsupported: {item}")
    return absolute


def digest(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def files_under(root: Path):
    safe_path(root)
    if not root.exists():
        return {}
    result = {}
    for folder, dirs, names in os.walk(root, followlinks=False):
        for name in dirs:
            safe_path(Path(folder) / name)
        for name in names:
            path = safe_path(Path(folder) / name)
            if not path.is_file():
                raise HandoffError(f"Non-regular history file: {path}")
            result[path.relative_to(root).as_posix()] = path
    return result


@dataclass
class Profile:
    name: str
    data: Path
    code: Path

    def scope(self):
        account = read_json(self.data / "config.json", {}).get("lastKnownAccountUuid")
        if not isinstance(account, str) or not UUID.fullmatch(account):
            raise HandoffError(f"Sign in to {self.name} before handing off sessions.")
        candidates = [self.code / ".claude.json"]
        if self.name == "main":
            candidates.insert(0, self.code.parent / ".claude.json")
        org = None
        for candidate in candidates:
            oauth = read_json(candidate, {}).get("oauthAccount", {})
            if oauth.get("accountUuid") == account:
                org = oauth.get("organizationUuid")
                break
        if not org:
            base = self.data / "claude-code-sessions" / account
            choices = [p.name for p in base.iterdir() if p.is_dir() and UUID.fullmatch(p.name)] if base.exists() else []
            if len(choices) != 1:
                raise HandoffError(f"Open the Code tab in {self.name} once so its active organization is known.")
            org = choices[0]
        if not isinstance(org, str) or not UUID.fullmatch(org):
            raise HandoffError(f"Invalid organization in {self.name}.")
        return safe_path(self.data / "claude-code-sessions" / account / org)


def profiles_at(root: Path, home: Path, roaming: Path):
    profiles = {"main": Profile("main", safe_path(roaming / "Claude"), safe_path(home / ".claude"))}
    if root.exists():
        for folder in root.iterdir():
            if folder.is_dir() and NAME.fullmatch(folder.name) and (folder / "profile.json").is_file():
                if folder.name == "main":
                    raise HandoffError("The profile name 'main' conflicts with the primary app.")
                profiles[folder.name] = Profile(folder.name, safe_path(folder / "electron"), safe_path(folder / "claude-code"))
    return profiles


def records_at(profile: Profile, all_scopes=False):
    base = safe_path(profile.data / "claude-code-sessions")
    candidates = base.glob("*/*/local_*.json") if all_scopes else profile.scope().glob("local_*.json")
    result = {}
    for path in candidates:
        safe_path(path)
        obj = read_json(path)
        sid = obj.get("sessionId")
        if not isinstance(sid, str) or not SESSION.fullmatch(sid) or path.name != sid + ".json":
            raise HandoffError(f"Invalid session record: {path}")
        prior = result.get(sid)
        if prior is None or obj.get("lastActivityAt", 0) > prior.get("lastActivityAt", 0):
            result[sid] = obj
    return result


def sanitized_record(record):
    obj = {k: v for k, v in record.items() if k in RECORD_FIELDS}
    # Re-evaluate permissions and account connectors in the destination app.
    obj["permissionMode"] = "default"
    return obj


def transcript_candidates(projects):
    index = {}
    for rel, path in projects.items():
        if path.suffix == ".jsonl" and UUID.fullmatch(path.stem):
            index.setdefault(path.stem, []).append(rel)
    return index


def prefix_of(shorter: Path, longer: Path):
    with shorter.open("rb") as a, longer.open("rb") as b:
        while chunk := a.read(1024 * 1024):
            if b.read(len(chunk)) != chunk:
                return False
    return True


def merge_projects(existing, incoming, reject_truncation=False):
    merged = dict(existing)
    for rel, path in incoming.items():
        old = merged.get(rel)
        if old is None or digest(old) == digest(path):
            merged[rel] = path
            continue
        if path.suffix == ".jsonl":
            if prefix_of(old, path):
                merged[rel] = path
            elif prefix_of(path, old):
                if reject_truncation:
                    raise HandoffError(f"The active conversation was rewound or truncated; no history was overwritten: {rel}")
            else:
                raise HandoffError(f"Divergent conversation copies; neither was overwritten: {rel}")
        else:
            merged[rel] = path
    return merged


def validate_transcript(path):
    """Validate every line before publishing a resumed conversation."""
    lines = 0
    with path.open("r", encoding="utf-8-sig") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except ValueError as exc:
                raise HandoffError(f"Incomplete or corrupt transcript, line {number}: {path}") from exc
            if not isinstance(value, dict):
                raise HandoffError(f"Invalid transcript record: {path}")
            lines += 1
    if not lines:
        raise HandoffError(f"Empty transcript: {path}")


class Transaction:
    def __init__(self, root, run_id):
        self.backup = root / "handoff-backups" / run_id
        self.journal = []

    def write(self, destination, source=None, value=None):
        destination = safe_path(destination)
        if source is not None and destination.exists() and digest(destination) == digest(source):
            return
        payload = None if source is not None else (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        if payload is not None and destination.exists() and destination.read_bytes() == payload:
            return
        number = len(self.journal)
        saved = self.backup / f"{number:06d}.bak" if destination.exists() else None
        self.backup.mkdir(parents=True, exist_ok=True)
        if saved:
            shutil.copy2(destination, saved)
        self.journal.append({"path": str(destination), "backup": str(saved) if saved else None})
        (self.backup / "journal.json").write_text(json.dumps(self.journal, indent=2), encoding="utf-8")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".tandem-" + uuid.uuid4().hex)
        try:
            if source is not None:
                before = source.stat()
                shutil.copy2(source, temporary)
                after = source.stat()
                if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size) or digest(temporary) != digest(source):
                    raise HandoffError("History changed during handoff; close all writers and try again.")
            else:
                temporary.write_bytes(payload)
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)

    def rollback(self):
        for entry in reversed(self.journal):
            destination = safe_path(Path(entry["path"]))
            if entry["backup"]:
                shutil.copy2(entry["backup"], destination)
            else:
                destination.unlink(missing_ok=True)


def check_remote_writers(records):
    for record in records.values():
        # These are daemon UUIDs, not OS process IDs. Never guess a PID or kill
        # a remote process from this metadata. Pause remote work in Claude first.
        if record.get("sshConfig") and (record.get("sshReattach") or {}).get("midTurn") is True:
            raise HandoffError("An SSH session is marked mid-turn. Stop that turn in the original app before switching.")


def prepare(root, profiles, target):
    if target not in profiles:
        raise HandoffError(f"Unknown destination profile: {target}")
    state = read_json(root / "handoff-state.json", {})
    store = root / "session-store"
    owner = state.get("owner", "main")
    if owner not in profiles:
        raise HandoffError("The last history owner is unavailable.")
    records = {}
    record_dir = store / "records"
    if record_dir.exists():
        records = {p.stem: read_json(p) for p in record_dir.glob("local_*.json")}
    sources = [profiles[owner]] if state else list(profiles.values())
    projects = files_under(store / "projects")
    raw_records = {}
    for source in sources:
        incoming = records_at(source, all_scopes=True)
        for sid, record in incoming.items():
            prior = raw_records.get(sid)
            if prior is None or record.get("lastActivityAt", 0) >= prior.get("lastActivityAt", 0):
                raw_records[sid] = record
        projects = merge_projects(projects, files_under(source.code / "projects"), reject_truncation=bool(state))
    for sid, obj in raw_records.items():
        if sid not in records or obj.get("lastActivityAt", 0) >= records[sid].get("lastActivityAt", 0):
            records[sid] = sanitized_record(obj)
    index = transcript_candidates(projects)
    available = {}
    unavailable_by_id = {x["sessionId"]: x for x in state.get("unavailable", [])}
    selected_transcripts = set()
    for sid, record in sorted(records.items()):
        cid = record.get("cliSessionId")
        matches = index.get(cid, []) if isinstance(cid, str) else []
        if len(matches) != 1:
            unavailable_by_id[sid] = {"sessionId": sid, "kind": "ssh" if record.get("sshConfig") else "local", "reason": "Transcript absent" if not matches else "Ambiguous transcript"}
            continue
        try:
            validate_transcript(projects[matches[0]])
        except HandoffError:
            unavailable_by_id[sid] = {"sessionId": sid, "kind": "ssh" if record.get("sshConfig") else "local", "reason": "Transcript fails JSON validation"}
            continue
        available[sid] = record
        unavailable_by_id.pop(sid, None)
        selected_transcripts.add(matches[0])
    return {
        "state": state, "owner": owner, "target": profiles[target], "scope": profiles[target].scope(),
        "records": available, "unavailable": list(unavailable_by_id.values()), "projects": projects,
        "transcripts": selected_transcripts, "raw_records": raw_records,
    }


def summary(plan):
    return {"source": plan["owner"], "target": plan["target"].name, "sessions": len(plan["records"]),
            "localSessions": sum(not r.get("sshConfig") for r in plan["records"].values()),
            "sshSessions": sum(bool(r.get("sshConfig")) for r in plan["records"].values()),
            "unavailable": plan["unavailable"], "historyBytes": sum(p.stat().st_size for p in plan["projects"].values()),
            "sshWorkerStateVerified": False if any(r.get("sshConfig") for r in plan["records"].values()) else None}


def execute(root, profiles, target, verify_remote=True):
    root = safe_path(root)
    root.mkdir(parents=True, exist_ok=True)
    lock = root / "handoff.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as exc:
        raise HandoffError("Another handoff holds the lock. No files were changed.") from exc
    os.close(fd)
    tx = Transaction(root, datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S-") + uuid.uuid4().hex[:8])
    try:
        plan = prepare(root, profiles, target)
        if not plan["records"]:
            raise HandoffError("No complete session history is available for handoff.")
        if verify_remote:
            check_remote_writers({sid: r for sid, r in plan["raw_records"].items() if sid in plan["records"]})
        for rel in plan["transcripts"]:
            validate_transcript(plan["projects"][rel])
        # The destination must not have developed a separate branch while inactive.
        expected = plan["state"].get("published", {}).get(target, {})
        for rel, old_hash in expected.items():
            path = plan["target"].code / "projects" / rel
            if path.exists() and digest(path) != old_hash:
                incoming = plan["projects"].get(rel)
                if incoming is None or digest(path) != digest(incoming):
                    raise HandoffError("Destination history changed while inactive; no copy was overwritten.")
        store = root / "session-store"
        published = {}
        for rel, source in plan["projects"].items():
            canonical = store / "projects" / rel
            if source != canonical:
                tx.write(canonical, source=source)
            tx.write(plan["target"].code / "projects" / rel, source=canonical)
            published[rel] = digest(canonical)
        for sid, record in plan["records"].items():
            tx.write(store / "records" / (sid + ".json"), value=record)
            tx.write(plan["scope"] / (sid + ".json"), value=record)
        result = summary(plan)
        result["backup"] = str(tx.backup)
        state = plan["state"]
        state.update({"version": 1, "owner": target, "updated": datetime.now(timezone.utc).isoformat(), "lastResult": result, "unavailable": plan["unavailable"]})
        state.setdefault("published", {})[target] = published
        tx.write(root / "handoff-state.json", value=state)
        tx.write(tx.backup / "result.json", value=result)
        return result
    except Exception:
        tx.rollback()
        raise
    finally:
        lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    try:
        root = safe_path(args.root)
        profiles = profiles_at(root, Path(os.environ["USERPROFILE"]), Path(os.environ["APPDATA"]))
        if args.preview:
            result = summary(prepare(root, profiles, args.target))
        else:
            # This script is also safe to invoke directly: never publish into a
            # live app or share a transcript with a separate CLI writer.
            query = "@(Get-CimInstance Win32_Process -Filter \"Name='claude.exe'\" | Select-Object -ExpandProperty ProcessId) | ConvertTo-Json -Compress"
            live = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", query], capture_output=True, text=True, timeout=20)
            if live.returncode or live.stdout.strip() not in ("", "[]", "null"):
                raise HandoffError("Quit all Claude desktop and CLI instances before handing off history.")
            result = execute(root, profiles, args.target)
        print(json.dumps(result))
    except (HandoffError, OSError) as exc:
        print(json.dumps({"error": str(exc)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
