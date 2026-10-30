# tandem-claude-desktop

Run Claude Desktop accounts side by side on Windows, with a separate login and data folder for each profile. Unofficial; not affiliated with Anthropic.

**Looking for ChatGPT?** Use the companion [tandem-chatgpt-desktop](https://github.com/jiahaozhang2025/tandem-chatgpt-desktop) launcher. Each project has its own installer and releases.

This Claude version also includes browser sign-in routing and optional sequential Code-history handoff between accounts.

## Open all accounts

For recurring startup or missing-icon problems, see [the diagnosis and troubleshooting notes](TROUBLESHOOTING.md).

After installing or upgrading, use **Claude (All Accounts)** on your desktop or Start menu. It opens your primary account and every configured profile. Accounts with a visible window are skipped without activating or restarting them. An account running only in the background is reactivated and checked for a visible window, without restarting it. You can also run:

```powershell
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" launch-all
```

This command opens independent account windows; it does not transfer or merge conversation history. Other profiles are still attempted if one fails, and failures are reported. Installers create the shortcuts automatically; use `-NoAllAccountsShortcut` to opt out. `-Root` selects which profile collection the shortcut opens. Uninstall removes its own All Accounts shortcuts while preserving links reassigned to another root.

## Install and use

Requires Windows PowerShell 5.1 and the Microsoft Store Claude package (`Claude`). Separate startup was tested locally with Claude 3.1623.1.0, 3.6556.1.0 and 3.6556.2.0. Other installation types are not currently supported.

```powershell
git clone https://github.com/jiahaozhang2025/tandem-claude-desktop.git
cd tandem-claude-desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" new account2 -Label "Account 2" -Color Blue
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" launch account2
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" signin account2
```

Open **Claude (Account 2)** on the desktop or Start menu for ordinary use. For first sign-in or after signing out, run `claude-profile signin account2`; it opens the profile and prepares callback routing for five minutes. Complete the normal browser login; the next login callback goes to Account 2 and normal link handling is restored. Your usual Claude icon continues to open your main profile.

| Command | Behavior |
| --- | --- |
| `new <name> [-Label <text>] [-Color <color>]` | Create or refresh profile shortcuts, retaining profile data |
| `launch-all` | Open every configured account, skipping visible windows and reactivating hidden accounts |
| `launch <name>` | Launch the profile, or activate its running instance |
| `signin <name>` | Temporarily route the next browser login callback to this running profile |
| `cancel-signin` | Restore normal Claude link handling immediately |
| `switch <main\|name> [-Preview]` | Hand off saved Code history to the other account, then open it |
| `taskbar [grouped\|separate] [-Disable]` | Save the taskbar grouping choice and update the running windows and account shortcuts |
| `list` | List profiles and running status; does not inspect credentials |
| `stop <name>` | Force-stop only that profile and its descendants; save work first |
| `remove <name> [-KeepData] [-Force]` | Remove shortcuts and optionally profile data, with confirmation |
| `doctor [-Deep]` | Check installation and static compatibility hints |

Every command accepts `-Root <folder>` (default `%USERPROFILE%\tandem-claude-desktop`). Names use letters, digits, hyphens and underscores; reserved Windows device names are rejected. Colors: Orange, Blue, Green, Purple, Red, Teal, Pink, Gray. `new` also accepts `-NoDesktopShortcut` and `-NoStartMenuShortcut`.

## Sign-in troubleshooting

Windows normally opens `claude://` links in your main instance, even when login began in Account 2. `signin account2` temporarily routes the active Claude Store protocol registration through the local helper. It saves the registration's original command and activation delegate, forwards the next login callback unchanged to the running profile using `--user-data-dir`, then restores both original values. A hidden helper also restores them after five minutes if login is abandoned. It refuses registrations belonging to another app and does not change Windows' protected default-app selection. Unrelated Claude links continue to go to the main app.

If your browser already shows **Finish sign-in in the Claude app**, run `signin account2`, then select **Open Claude** again. If Chrome asks to open **Windows PowerShell**, allow it: that runs the installed local callback helper. If the callback has expired, start a fresh login from Account 2. No login URI is written to launcher scripts, metadata or logs. The URI is passed as an ordinary app launch argument, as in the normal Windows flow.

For email login, Anthropic also documents a [cross-device verification-code flow](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account). If that flow returns to an **Open Claude** button, prepare profile routing before clicking it.

An identity-provider error is not proof of a profile conflict. If the code flow also fails, test the same account in a private browser window and check [Claude's status](https://status.claude.com/). Organization-managed accounts may require their configured SSO flow. An isolated startup alone does not prove authentication succeeded.

## How it works

Launches the installed, unmodified executable inside its Store package using `Invoke-CommandInDesktopPackage -PreventBreakaway` and a small `cmd.exe` wrapper:

* `--user-data-dir=<profile>\electron` selects separate desktop cookies, local storage, app settings and instance lock.
* `CLAUDE_CONFIG_DIR=<profile>\claude-code` gives supported Claude Code components a separate settings directory.
* Windows shortcuts start the launcher with a hidden PowerShell window and a colored Claude icon.

The production app ignores `CLAUDE_USER_DATA_DIR`; this launcher does not rely on it. It does not copy logins, patch app files, inject scripts, enable debugging or modify system-wide environment variables.

Every new launch must have a matching desktop parent, live Electron children reporting the selected data folder, and fresh app writes inside that folder. A failed check closes only the matching profile process tree and reports the error. `doctor -Deep` is a static hint, not a substitute for this runtime check.

Profiles contain `electron/`, `claude-code/`, `profile.json`, colored icons, `launch.cmd` and `launcher.log`. Credentials are protected by the app's normal Windows mechanisms; these profiles are not a security boundary against other programs running as you.

## Taskbar grouping option

```powershell
# Separate colored icons for each account:
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" taskbar separate
# Restore the app's normal grouped taskbar button:
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" taskbar grouped
```

The choice is saved per profile root and survives future launches and upgrades. A fresh root uses the app's normal grouping until separate mode is selected. Running `taskbar` without a mode still selects separate mode; `taskbar -Disable` remains an alias for grouped mode. You can choose during installation with `install.ps1 -TaskbarMode Grouped` or `install.ps1 -TaskbarMode Separate`, optionally with `-Root`. Omitting that installer option preserves the existing choice.

Separate mode refreshes the account shortcuts and gives each account a different Windows taskbar identity. **Claude (Main)** uses an orange icon and other profiles use their selected color. Pin each account's desktop shortcut or running taskbar button separately if you want both icons available while an account is closed. Windows keeps copies of pinned shortcuts; if a pin retains the old layout after changing modes, unpin it and pin the refreshed shortcut. Use the account-specific shortcuts for profile switching.

Taskbar relaunches use the same account shortcut, preserving sequential history handoff when it is enabled. Changing taskbar groups does not synchronize two concurrent writers to the same coding conversation.

A hidden PowerShell helper maintains separate account identities on Claude's windows, including new windows. It starts with the companion launcher and exits after Claude has been closed for 30 seconds. It changes Windows shell properties and window icons without patching Claude or loading code into it. Grouped mode stops the helper and restores the live windows' previous taskbar properties without restarting Claude. The option does not change global taskbar settings or account isolation.

## Continue the same coding conversation under another account

Sequential session handoff requires **Python 3.10 or newer**. It preserves the Desktop session ID, Claude Code transcript ID, full available transcript, sidecars and working-folder paths. New turns carry back on the next switch. It is a snapshot handoff between accounts, not two windows controlling one running backend.

**Experimental:** transfer integrity, switching back, and history visibility in the other signed-in account have been checked locally. Sending a new model reply in a transferred session and reconnecting SSH sessions under the other account have not yet been verified. See [validation details](VALIDATION.md).

```powershell
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" switch account2 -Preview
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" switch account2
# Later, return with the updated conversation:
& "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\claude-profile.cmd" switch main
```

After the first handoff, use **Claude (Main)** and **Claude (Account 2)** on your desktop or Start menu. These shortcuts synchronize the last account's saved histories before opening the destination. Clicking the already active account's shortcut brings it forward. The vendor's original Claude shortcut bypasses synchronization.

Finish active turns before switching. The switch closes the desktop windows; it refuses to do so while a Code/CLI backend is still open. If asked, quit the source app normally from its tray menu, then use the other account's shortcut. The source and destination must both already be signed in and have initialized their Code tabs.

Only session metadata and `claude-code/projects` histories travel. Cookies, OAuth files, CLI credentials, account connector grants, bridge IDs and previous permission approvals stay separate. The destination uses its own signed-in account; it may ask for new permissions or connector setup. The underlying project files keep their original locations.

SSH history caches can travel, but **pause remote turns in the original app first**. The tool rejects sessions marked mid-turn, clears stale reattachment handles, and preserves the SSH host and working folder. It does not kill remote workers or verify their live status. Reconnecting and continuing an SSH session under the other account still requires validation on that host.

Missing, ambiguous or malformed transcripts are reported in the command result and `handoff-state.json` and remain untouched in their original profile. They are not presented as successfully transferred history. The tool refuses divergent transcript branches instead of overwriting one with the other. Independent edits in a previously published destination also block handoff, even when that account was opened outside the launcher. It does not merge competing turns or select a winner: keep each branch as a separate fork, or choose which copy to continue before reconciling. Preflight checks these conflicts and remote mid-turn flags before closing any windows, and the publish transaction checks them again after local writers stop. All Accounts opens windows without running this handoff. Per-file backups and a journal live under `handoff-backups/`; handled failures roll back the attempted transfer. A central copy lives under `session-store/`. A process lock prevents overlapping handoffs. These folders are local conversation data and are retained by the default uninstall.

The first handoff discovers saved records across the local profiles' existing account/organization folders. Later switches take updates to existing conversations from the last account used by the launcher. They also discover new conversations created in another profile, including through the native app shortcut, and import their transcripts and session-specific sidecars. Existing conversations edited outside the active profile are not merged through this discovery step. Use the companion shortcuts for this sequential workflow, and avoid separately editing the same conversation from another CLI or app instance.

The app install, browser extensions, system credentials and machine-level services remain shared. Taskbar groups can be separated as described above; other OS integrations remain shared. URL handling is shared except during the temporary sign-in operation described above. Concurrent Cowork VM behavior and authenticated Claude Code execution have not been validated. The launcher does not claim to isolate those services. Each instance uses additional memory. App updates can change behavior; the executable path is resolved again at each launch.

Profile paths must be ASCII, without `%`, and cannot pass through directory links. Profile removal deletes nested directory links themselves without traversing their targets.

Taskbar identity schema v2 also repairs icons owned by a previous helper process. Desktop, Start menu and private account links are refreshed on installation. If you retained an old pinned shortcut independently, repin the refreshed account shortcut to use the v2 identity.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\uninstall.ps1"
```

Keeps profile data by default. `-RemoveProfiles` also deletes the selected root's profiles; `-Force` skips confirmation. Pass the same `-Root` for a custom profile location. The source checkout and main Claude installation remain available.

## Development

```powershell
Import-Module Pester -MinimumVersion 5.5.0
Invoke-Pester .\tests -Output Detailed
python -m unittest discover -s tests -p test_session_handoff.py -v
```

Tests use temporary folders and mock app and process operations. They never launch Claude or access real profiles. The CI definition runs Pester on Windows PowerShell 5.1 and PowerShell 7, plus PSScriptAnalyzer.

[Changelog](CHANGELOG.md) · [Validation and known limits](VALIDATION.md)

MIT license.
