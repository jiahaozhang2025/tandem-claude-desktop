# Changelog

## 0.3.5 - 2026-10-30

* Fix blank running-window taskbar icons after a helper restart. A new helper now claims each window even when old shell properties already match, validates live icon handles, and repairs icons overwritten by the app.
* Load and set live icons before publishing the taskbar group ID; reject invalid icon files before changing metadata. Restoration does not reinstate dead handles or inherited companion IDs.
* Move to stable v2 taskbar identities to replace stale cached group images from the old implementation. Refresh all managed account shortcuts during installation so their IDs match running windows.
* Add separate-process regression tests that leave taskbar metadata behind after the icon-owning helper exits, including old-to-new identity restoration.


## 0.3.4 - 2026-10-29

* Notify Windows with SHCNE_UPDATEITEM and SHCNF_FLUSH after creating or rewriting account shortcuts, including icon-only updates, so other Explorer views can refresh cached images.
* Add native regression tests using an off-screen window that changes between hidden, visible and tool-window states, plus repeat-shortcut-update notification coverage.


## 0.3.3 - 2026-10-29

* Fix All Accounts skipping a hidden background account: check visible taskbar windows, reactivate hidden accounts through their normal launch command, and verify a window appears.
* Use persistent local icons for Main and All Accounts shortcuts instead of versioned Store executable paths. Retain older icon resources for pinned shortcuts and track the current profile icon explicitly.
* Refresh Main shortcuts and restart only the shell helper during installer upgrades, preserving running apps and taskbar preferences. All Accounts also starts a missing taskbar helper.
* Add per-account state/action/process-ID diagnostics in launcher-events.log and tests for hidden accounts and removed package folders.

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
