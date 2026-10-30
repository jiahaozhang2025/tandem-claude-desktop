@{
    RootModule           = 'tandem-claude-desktop.psm1'
    ModuleVersion        = '0.3.5'
    GUID                 = 'bf128dc9-e536-46be-942d-b2ceba829cba'
    Author               = 'Jiahao Zhang'
    Copyright            = '(c) 2026 Jiahao Zhang. MIT License.'
    Description          = 'Run the Claude desktop app for Windows as several isolated instances, one per account, side by side. Unofficial; not affiliated with Anthropic.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'Start-ClaudeAllAccounts'
        'New-ClaudeAllAccountsShortcut'
        'New-ClaudeProfile'
        'Start-ClaudeProfile'
        'Stop-ClaudeProfile'
        'Get-ClaudeProfile'
        'Remove-ClaudeProfile'
        'Test-ClaudeProfileSupport'
        'Enable-ClaudeProfileSignIn'
        'Disable-ClaudeProfileSignIn'
        'Switch-ClaudeProfile'
        'Set-ClaudeProfileTaskbar'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Claude', 'Desktop', 'Windows', 'MultiAccount', 'Profiles')
            LicenseUri = 'https://github.com/jiahaozhang2025/tandem-claude-desktop/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jiahaozhang2025/tandem-claude-desktop'
        }
    }
}
