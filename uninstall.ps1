<#
.SYNOPSIS
  Uninstalls claude-profile for the current user.

.DESCRIPTION
  Removes every profile's shortcuts (they would point at deleted scripts) and the
  installed scripts. Profile folders, including their logins, are kept unless you add
  -RemoveProfiles. Your main Claude app and its login are never touched.
  -Force skips the confirmation prompt (-Confirm:$false does not survive powershell -File).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\tandem-claude-desktop\uninstall.ps1"
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$Destination = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\tandem-claude-desktop'),
    [string]$Root,
    [switch]$RemoveProfiles,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$manifest = Join-Path -Path $destinationPath -ChildPath 'tandem-claude-desktop\tandem-claude-desktop.psd1'
if (-not (Test-Path -LiteralPath $manifest)) { throw "claude-profile is not installed in $destinationPath." }

$installedModule = Import-Module -Name $manifest -Force -PassThru
$common = @{}
if ($Root) { $common.Root = $Root }
$profiles = @(Get-ClaudeProfile @common)

$action = "Uninstall claude-profile and remove the shortcuts of $($profiles.Count) profile(s), keeping their data"
if ($RemoveProfiles) { $action = "Uninstall claude-profile and delete $($profiles.Count) profile(s) including their logins" }

if ($PSCmdlet.ShouldProcess($destinationPath, $action)) {
    Disable-ClaudeProfileSignIn -Confirm:$false
    $historyRoot = $Root
    if (-not $historyRoot) { $historyRoot = Join-Path $env:USERPROFILE 'tandem-claude-desktop' }
    & $installedModule { param($R) Remove-HandoffShortcut -Root $R } $historyRoot
    foreach ($p in $profiles) {
        Remove-ClaudeProfile -Name $p.Name -KeepData:(-not $RemoveProfiles) -Confirm:$false @common
    }
    & $installedModule { param($P) Remove-ProfileTree -Path $P -Boundary (Split-Path $P -Parent) } $destinationPath
    Remove-Module -ModuleInfo $installedModule -Force
    Write-Output "Removed $destinationPath"
    if (-not $RemoveProfiles -and $profiles.Count -gt 0) {
        Write-Output "Profile data was kept in $(Split-Path -Path $profiles[0].Path -Parent)."
    }
}
