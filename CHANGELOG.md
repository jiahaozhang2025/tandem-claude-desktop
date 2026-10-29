# Changelog

## 0.3.2 — 2026-10-29

* Add `claude-profile launch-all` and Desktop/Start menu **Claude (All Accounts)** shortcuts, installed by default. Open only missing accounts; skip running accounts without activating or restarting them.
* Discover all configured profiles on each use and report launch failures after attempting the other accounts.
* Check history conflicts and remote turns before closing windows for a handoff; repeat validation inside the publish transaction. Independent conversation branches remain intact.

## 0.3.1 — 2026-10-26

* Add explicit persistent taskbar choices: `taskbar grouped` and `taskbar separate`.
* Add installer option `-TaskbarMode Grouped|Separate`; upgrades preserve the saved preference when it is omitted.
* Retain `taskbar -Disable` as an alias for grouped mode. Switching modes updates live windows without restarting Claude.

## 0.3.0 — 2026-10-26

* Add optional separate taskbar groups and colored running-window icons for each Claude account.
* Give account shortcuts matching taskbar identities so each account can be pinned separately. Pinned-icon relaunches keep using the account's history-switching command.
* Maintain identities on new Claude windows through a hidden helper that exits when Claude is closed. Disabling the feature restores the live windows' previous taskbar properties.
* Add native shell-property integration checks for shortcut preservation and window-property restoration.

## 0.2.1 — 2026-10-26

* Fix missing sessions created in another account through the native Claude shortcut while the launcher still considered a different profile active.
* Discover new session IDs across profiles and import their transcripts and session-specific sidecars without merging unrelated edits to existing conversations.
* Check for newly created sessions before merely activating an already running profile, so clicking the destination shortcut can synchronize those sessions too.
* Retain credential isolation, transcript conflict checks, SSH mid-turn guards, and transaction backups.

## 0.2.0 — 2026-10-22

First standalone preview release, adapted from the MIT-licensed [tandem-chatgpt-desktop](https://github.com/jiahaozhang2025/tandem-chatgpt-desktop) project.

* Run multiple Microsoft Store Claude Desktop accounts with separate Electron data and Claude Code configuration folders.
* Create colored desktop and Start menu shortcuts and verify profile isolation after launching.
* Temporarily route browser login callbacks to the chosen profile, restoring the original Windows registration after completion, cancellation or timeout.
* Add experimental sequential Code-history handoff with preserved conversation IDs, separate credentials, transcript validation, conflict checks, backups and rollback.
* Refuse handoff while local Code/CLI backends are open; reject saved SSH sessions marked mid-turn.

History transfer and visibility in the other account have been checked locally. New model replies and SSH reconnection under the other account remain unverified. See [VALIDATION.md](VALIDATION.md).
