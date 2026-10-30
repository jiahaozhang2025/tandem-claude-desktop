# Recurring launch and icon problems

## Diagnosis on October 29, 2026

Main and All Accounts shortcuts stored icon paths inside versioned Microsoft Store installation folders. Updates removed those folders, leaving the launcher itself intact but its icon missing. Icons now live under the local profile root, outside the app package. Older icon hashes are retained for pinned shortcut copies.

The companion ChatGPT launcher also exposed an All Accounts bug shared by this implementation: it treated a running process as an open account even when the app window was hidden. The fix checks for a visible taskbar window, sends the normal account launch request to reactivate hidden accounts, and verifies that a window appears. Floating tool windows do not count as normal account windows. Visible or minimized windows are left alone.

These are separate from Claude's sequential history handoff. The individual account shortcuts may still run `switch`, which checks and transfers saved histories and closes desktop windows only after preflight. All Accounts uses normal launches and never invokes that history transfer. Conflicting histories are retained, not automatically merged; preflight reports a conflict before closing windows. This does not make two accounts concurrent writers to one running conversation.

## Repairs and diagnostics

Reinstalling the companion launcher repairs Main and All Accounts shortcuts with durable icons and refreshes only the shell helper. Running account apps and the grouped/separate preference are preserved. `-NoAllAccountsShortcut` opts out of this shortcut and helper maintenance.

Under `%USERPROFILE%\tandem-claude-desktop`:

* `launcher-events.log` records each account's Visible, Hidden or Stopped state, action and process IDs during All Accounts use. Hidden + Activate should be followed by Visible + Ready. Failure is reported instead of treating a background process as an open window.
* `<profile>\launcher.log` records the installed app version and profile launch checks.
* `taskbar.log`, if present, records failures applying separate shell identities.
* `handoff-state.json` and `handoff-backups` concern history transfer, not ordinary window activation. Do not delete them to repair an icon.

Regression tests cover hidden background accounts, a removed vendor package, visibility timeouts that do not stop initialized accounts, and retained resources for taskbar pins. The earlier tests verified processes and already visible windows, which missed these recurrence paths.
