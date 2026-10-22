# Validation — October 22, 2026

Tested locally on Windows with the Microsoft Store Claude package (`Claude`), versions 3.1623.1.0 and 3.6556.1.0. These checks apply to this implementation and those app versions; later Claude updates can change compatibility.

## Automated checks

* Pester 5.9.1: 50 tests passed in Windows PowerShell 5.1 and PowerShell 7. Coverage includes path validation, process matching, child data-directory verification, startup timeout cleanup, profile removal without following directory links, retained settings, callback routing and restoration, read-only handoff preview, and refusing to stop windows while a Code/CLI backend is open.
* Python 3.13: 17 handoff tests passed. Coverage includes transcript/session ID continuity, new synthetic turns surviving a switch back, credential isolation, sidecars, transaction rollback, missing or invalid history reporting, divergent/rewound history rejection, locking, and SSH mid-turn refusal.
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

## Remaining limits

The handoff moves saved history rather than a running backend. Account cookies, OAuth/CLI credentials and connector grants are not copied.

Sending a new model reply in a transferred session under the other account has not been validated. SSH host/working-folder metadata and valid cached histories transferred, but reconnecting and continuing a real SSH session under the other account have not been validated. Remote workers are not killed or probed by guessed OS PIDs; pause remote turns before switching.

Concurrent Cowork VM behavior and non-Store Claude installations have not been validated. Session handoff remains experimental.
