<#
.SYNOPSIS
  Installs claude-profile for the current user (no admin rights needed).

.DESCRIPTION
  Copies the scripts to %LOCALAPPDATA%\Programs\tandem-claude-desktop (or -Destination)
  so profile shortcuts keep working after this folder is moved or deleted. Running it
  again upgrades in place; existing profiles and shortcuts are kept.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Destination = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\tandem-claude-desktop')
)

$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
if ($destinationPath -eq [IO.Path]::GetFullPath($source).TrimEnd('\')) {
    throw 'Run install.ps1 from the downloaded repository, not from the install folder.'
}

if ($PSCmdlet.ShouldProcess($destinationPath, 'Install claude-profile')) {
    $moduleTarget = Join-Path -Path $destinationPath -ChildPath 'tandem-claude-desktop'
    $null = New-Item -ItemType Directory -Force -Path $moduleTarget
    foreach ($file in 'claude-profile.ps1', 'profile-auth.ps1', 'session-handoff.py', 'uninstall.ps1', 'README.md', 'LICENSE') {
        Copy-Item -LiteralPath (Join-Path -Path $source -ChildPath $file) -Destination $destinationPath -Force
    }
    foreach ($file in 'tandem-claude-desktop.psd1', 'tandem-claude-desktop.psm1') {
        Copy-Item -LiteralPath (Join-Path -Path $source -ChildPath "tandem-claude-desktop\$file") -Destination $moduleTarget -Force
    }
    # Lets cmd.exe and the Run dialog call the tool without typing powershell.exe.
    Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'claude-profile.cmd') -Encoding Ascii -Value @(
        '@echo off'
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-profile.ps1" %*'
    )
    # Copies keep the "downloaded from the internet" mark of a downloaded zip, which makes
    # Import-Module fail under a RemoteSigned execution policy.
    Get-ChildItem -LiteralPath $destinationPath -Recurse -File | Unblock-File

    $cli = Join-Path -Path $destinationPath -ChildPath 'claude-profile.cmd'
    Write-Output "Installed to $destinationPath"
    Write-Output ''
    Write-Output 'Create a profile for your second account (adds Start menu and desktop shortcuts):'
    Write-Output "  `"$cli`" new account2 -Label `"Account 2`""
    Write-Output 'Then open the new shortcut and sign in. Check your setup any time with:'
    Write-Output "  `"$cli`" doctor -Deep"
}
