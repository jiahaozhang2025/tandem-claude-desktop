# Changelog

## 0.2.0 — 2026-10-22

First standalone preview release, adapted from the MIT-licensed [tandem-chatgpt-desktop](https://github.com/jiahaozhang2025/tandem-chatgpt-desktop) project.

* Run multiple Microsoft Store Claude Desktop accounts with separate Electron data and Claude Code configuration folders.
* Create colored desktop and Start menu shortcuts and verify profile isolation after launching.
* Temporarily route browser login callbacks to the chosen profile, restoring the original Windows registration after completion, cancellation or timeout.
* Add experimental sequential Code-history handoff with preserved conversation IDs, separate credentials, transcript validation, conflict checks, backups and rollback.
* Refuse handoff while local Code/CLI backends are open; reject saved SSH sessions marked mid-turn.

History transfer and visibility in the other account have been checked locally. New model replies and SSH reconnection under the other account remain unverified. See [VALIDATION.md](VALIDATION.md).
