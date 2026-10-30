# Validation

## Shell icon refresh verification, October 29, 2026

* 83 Pester tests pass on Windows PowerShell 5.1 and PowerShell 7. New native tests verify hidden -> visible -> hidden transitions, reject visible tool-only windows, and deliver shell change notifications without changing shortcut arguments. These windows belong to the test runner, are placed off-screen and never activate a vendor app.
* Claude Main was visually confirmed with an orange icon in File Explorer's Desktop folder. All five cached ICO frames (16, 24, 32, 48, 256 pixels) contain visible image pixels. Explicit shell notifications were delivered to its Desktop and Start menu shortcuts.
* Testing these known failure paths cannot guarantee compatibility with every future vendor or Windows update. Process/window states and failed activations remain logged for diagnosis.


## Recurring launch and icon fixes, October 29, 2026

* 80 Pester tests pass on PowerShell 7. Regression tests simulate a running hidden account, visibility timeout without process termination, and removal of a vendor package after shortcut creation. Older colored icon resources are retained for pins.
* Before remediation, Main and All Accounts shortcut icon paths referenced removed Store versions. ChatGPT Account 2 had a live parent process and valid profile writes but zero visible taskbar windows. The old All Accounts command reported AlreadyRunning and did nothing; the normal account launch revealed its existing window with the same parent PID. This reproduced the cause without restarting either account.
* The visibility check excludes tool windows such as floating overlays. Startup file writes alone are no longer treated as proof of a usable ChatGPT window.


## October 29, 2026

* 76 Pester tests passed on Windows PowerShell 5.1 and PowerShell 7; 26 Python handoff tests passed. PSScriptAnalyzer found no warnings or errors in the production scripts.
* All Accounts coverage includes neither/either/both accounts running, custom roots with spaces, unmanaged profiles, partial launch failure, WhatIf, shortcut creation, and safe uninstall ownership checks. App launches in these tests are mocked.
* Installed Desktop and Start menu All Accounts shortcuts for both companion apps. Live `launch-all` calls with both accounts already running left all four desktop parent process IDs unchanged. Taskbar preference and Claude handoff-state hashes were unchanged by the installer upgrades.
* Claude 4.29.0.0 ran both signed-in profiles. The All Accounts command bypasses history transfer. Known conflicts and saved SSH mid-turn flags are checked before closing any windows for a sequential handoff and rechecked at publication; tests verify conflicts leave windows and history untouched.
* Existing independent conversation copies were not reconciled, forked, or overwritten. Closed-account launch combinations were tested with mocks rather than interrupting live work.

## October 26, 2026

Tested locally on Windows with the Microsoft Store Claude package (`Claude`), versions 3.1623.1.0, 3.6556.1.0 and 3.6556.2.0. These checks apply to this implementation and those app versions; later Claude updates can change compatibility.

## Automated checks

* Pester 5.9.1: 63 tests passed in Windows PowerShell 5.1 and PowerShell 7. Coverage includes path validation, process matching, child data-directory verification, startup timeout cleanup, profile removal without following directory links, retained settings, callback routing and restoration, read-only handoff preview, refusing to stop windows while a Code/CLI backend is open, and checking for new sessions before activating the current profile. Taskbar checks cover saved grouped/separate choices, the legacy Disable alias, invalid modes and WhatIf, stable per-profile IDs, shortcut preservation, native property setting/restoration on an invisible test window, stale helper PID rejection, the exported setup command, and WhatIf for primary-account launches.
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
* Version 0.3.1 completed a live `grouped -> separate` round trip on both accounts: grouped mode removed the separate window identities, and separate mode restored distinct identities for each account. The desktop process IDs stayed unchanged. Reinstalling without `-TaskbarMode` preserved the saved preference file byte for byte.

## Remaining limits

The handoff moves saved history rather than a running backend. Account cookies, OAuth/CLI credentials and connector grants are not copied.

Sending a new model reply in a transferred session under the other account has not been validated. SSH host/working-folder metadata and valid cached histories transferred, but reconnecting and continuing a real SSH session under the other account have not been validated. Remote workers are not killed or probed by guessed OS PIDs; pause remote turns before switching.

Concurrent Cowork VM behavior and non-Store Claude installations have not been validated. Session handoff remains experimental.
