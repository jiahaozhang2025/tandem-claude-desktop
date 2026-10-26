# Validation — October 26, 2026

Tested locally on Windows with the Microsoft Store Claude package (`Claude`), versions 3.1623.1.0, 3.6556.1.0 and 3.6556.2.0. These checks apply to this implementation and those app versions; later Claude updates can change compatibility.

## Automated checks

* Pester 5.9.1: 59 tests passed in Windows PowerShell 5.1 and PowerShell 7. Coverage includes path validation, process matching, child data-directory verification, startup timeout cleanup, profile removal without following directory links, retained settings, callback routing and restoration, read-only handoff preview, refusing to stop windows while a Code/CLI backend is open, and checking for new sessions before activating the current profile. Taskbar checks cover stable per-profile IDs, shortcut preservation, native property setting/restoration on an invisible test window, stale helper PID rejection, the exported setup command, and WhatIf for primary-account launches.
* Python 3.13: 23 handoff tests passed. Coverage includes transcript/session ID continuity, new synthetic turns surviving a switch back, credential isolation, sidecars, transaction rollback, missing or invalid history reporting, divergent/rewound history rejection, locking, and SSH mid-turn refusal. Regression tests cover discovering new local and SSH sessions outside the last active profile without importing unrelated inactive edits or conflicting transcripts.
* PSScriptAnalyzer 1.25.0: no warnings or errors in the module, CLI, callback helper, installer or uninstaller.

The repository's CI runs the Python tests, Pester on both PowerShell versions, and PSScriptAnalyzer independently of the ChatGPT companion project.

## Manual checks

* An additional profile launched while the main app and another profile were already running. Live child processes and fresh writes confirmed the selected data directory. Stopping the temporary profile left the other instances running.
* Temporary installation and uninstallation retained profile data as intended. The per-user installation upgraded in place, and desktop/Start menu shortcuts pointed to the installed launcher.
* The colored icon was visually checked for contrast.
* A real Windows protocol launch invoked the sign-in callback helper. Cancellation restored the original AppX command and activation delegate. Sign-in to the second account was confirmed to work.
* Sequential handoff completed the real sequence `main -> account2 -> main -> account2`. Both account/organization indexes contained 26 transferred sessions: 15 local and 11 SSH histories. Desktop and Claude Code transcript IDs were retained.
* All 415 copied project-history files (825,967,277 bytes) matched their recorded SHA-256 hashes. Existing source records were retained.
* History visibility in the second account's Code tab was confirmed by the user.
* Seven records lacked a local transcript and one SSH cache contained a damaged NUL-filled line. These were reported as unavailable; originals were not repaired, truncated or deleted.
* On October 26, the 0.2.1 fix discovered a new SSH session created outside the last active profile and transferred its complete 6,967,714-byte cached transcript with matching SHA-256, retained Desktop/CLI IDs and no stale reattachment handle. The destination was confirmed signed in to its own account, and the transferred conversation opened there with its history and SSH environment visible. No model message was sent for this check.
* Version 0.3.0 was enabled on live Claude 3.6556.2.0 windows without restarting the existing account. Two desktop instances were confirmed to have different explicit taskbar identities, labels and colored icon resources. Desktop, Start menu and private relaunch shortcuts use the matching per-account identities; the private shortcut arguments retain the history-switching command. Automated taskbar pinning was not completed; Windows manages the user's pinned items.

## Remaining limits

The handoff moves saved history rather than a running backend. Account cookies, OAuth/CLI credentials and connector grants are not copied.

Sending a new model reply in a transferred session under the other account has not been validated. SSH host/working-folder metadata and valid cached histories transferred, but reconnecting and continuing a real SSH session under the other account have not been validated. Remote workers are not killed or probed by guessed OS PIDs; pause remote turns before switching.

Concurrent Cowork VM behavior and non-Store Claude installations have not been validated. Session handoff remains experimental.
