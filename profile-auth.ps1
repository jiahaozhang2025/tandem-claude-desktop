#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$RegistrationId,
    [string]$Uri,
    [switch]$Expire
)
$ErrorActionPreference = 'Stop'
try {
    $module = Import-Module (Join-Path $PSScriptRoot 'tandem-claude-desktop') -Force -PassThru
    if ($Expire) {
        # A short-lived hidden helper restores normal routing if login is abandoned.
        Start-Sleep -Seconds 300
        & $module { param($Id) Remove-ProfileSignInRoute -RegistrationId $Id } $RegistrationId.ToString()
    } else {
        & $module { param($Id, $Link) Invoke-ProfileSignInCallback -RegistrationId $Id -Uri $Link } $RegistrationId.ToString() $Uri
    }
} catch {
    # Do not display exception context: it could contain the one-time login URI.
    if (-not $Expire) {
        Add-Type -AssemblyName System.Windows.Forms
        $null = [System.Windows.Forms.MessageBox]::Show('The callback could not be delivered. Run claude-profile cancel-signin, then prepare sign-in again with claude-profile signin account2.', 'Claude profile sign-in', 'OK', 'Error')
    }
    exit 1
}
