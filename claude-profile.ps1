<#
.SYNOPSIS
  claude-profile: run several Claude desktop accounts side by side on Windows.

.DESCRIPTION
  claude-profile new <name> [-Label <text>] [-Color <color>]
                             [-NoDesktopShortcut] [-NoStartMenuShortcut]
  claude-profile launch <name>
  claude-profile signin <name>
  claude-profile cancel-signin
  claude-profile switch <main|name> [-Preview]
  claude-profile taskbar [-Disable]
  claude-profile list
  claude-profile stop <name>
  claude-profile remove <name> [-KeepData] [-Force]
  claude-profile doctor [-Deep]

  Every command accepts -Root <folder> (default: %USERPROFILE%\tandem-claude-desktop).
  Colors: Orange, Blue, Green, Purple, Red, Teal, Pink, Gray.

.EXAMPLE
  claude-profile new work -Label Work -Color Blue
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('new', 'launch', 'signin', 'cancel-signin', 'switch', 'taskbar', 'list', 'stop', 'remove', 'doctor', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1)][string]$Name,
    [string]$Label,
    [string]$Color,
    [string]$Root,
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut,
    [switch]$KeepData,
    [switch]$Force,
    [switch]$Deep,
    [switch]$Preview,
    [switch]$Disable,
    # Used by shortcuts: report errors in a message box because there is no console.
    [switch]$Gui
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    Get-Help -Name $PSCommandPath -Detailed | Out-String | Write-Output
}

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'tandem-claude-desktop\tandem-claude-desktop.psd1') -Force
    $common = @{}
    if ($Root) { $common.Root = $Root }
    if ($Command -in 'new', 'launch', 'signin', 'switch', 'stop', 'remove' -and -not $Name) {
        throw "'$Command' needs a profile name, for example: claude-profile $Command work"
    }

    switch ($Command) {
        'new' {
            $options = @{ Name = $Name }
            if ($Label) { $options.Label = $Label }
            if ($Color) { $options.Color = $Color }
            $result = New-ClaudeProfile @options @common -NoDesktopShortcut:$NoDesktopShortcut -NoStartMenuShortcut:$NoStartMenuShortcut
            $result | Format-List | Out-String | Write-Output
            if ($null -ne $result) {
                Write-Output "Next: open the 'Claude ($($result.Label))' shortcut (or run 'claude-profile launch $Name') and sign in."
            }
        }
        'launch' { $null = Start-ClaudeProfile -Name $Name @common }
        'signin' {
            $null = Start-ClaudeProfile -Name $Name @common
            Enable-ClaudeProfileSignIn -Name $Name @common | Format-List
        }
        'cancel-signin' { Disable-ClaudeProfileSignIn }
        'switch' { Switch-ClaudeProfile -Name $Name -Preview:$Preview @common | Format-List }
        'taskbar' { Set-ClaudeProfileTaskbar -Disable:$Disable @common | Format-List }
        'list' { Get-ClaudeProfile @common | Format-Table -AutoSize | Out-String | Write-Output }
        'stop' { Stop-ClaudeProfile -Name $Name @common }
        'remove' {
            if ($Force) { Remove-ClaudeProfile -Name $Name -KeepData:$KeepData -Confirm:$false @common }
            else { Remove-ClaudeProfile -Name $Name -KeepData:$KeepData @common }
        }
        'doctor' { Test-ClaudeProfileSupport -Deep:$Deep @common | Format-Table -AutoSize -Wrap | Out-String | Write-Output }
        default { Show-Usage }
    }
} catch {
    $message = $_.Exception.Message
    if ($Gui) {
        Add-Type -AssemblyName System.Windows.Forms
        $title = 'tandem-claude-desktop'
        if ($Name) { $title = "Claude ($Name)" }
        $null = [System.Windows.Forms.MessageBox]::Show($message, $title, 'OK', 'Error')
    } else {
        Write-Error -Message $message -ErrorAction Continue
    }
    exit 1
}
