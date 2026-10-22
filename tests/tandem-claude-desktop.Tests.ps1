#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tandem-claude-desktop') -Force
    function New-TestProfile([string]$Root) {
        $dir = Join-Path $Root 'work'
        $null = New-Item -ItemType Directory -Force -Path "$dir\electron", "$dir\claude-code"
        '{"name":"work","label":"Work","shortcuts":[]}' | Set-Content -LiteralPath "$dir\profile.json"
    }
}

Describe 'Profile paths' {
    It 'rejects invalid and Windows device names: <_>' -ForEach @('', '..', 'a/b', 'a\b', 'a b', '-x', 'CON', 'nul', 'COM1', ('a' * 65)) {
        InModuleScope tandem-claude-desktop -Parameters @{ N = $_ } {
            param($N)
            { Assert-ProfileName $N } | Should -Throw '*Invalid profile name*'
        }
    }
    It 'accepts valid names: <_>' -ForEach @('a', 'account2', 'Work_1', 'x-y', ('a' * 64)) {
        InModuleScope tandem-claude-desktop -Parameters @{ N = $_ } {
            param($N)
            { Assert-ProfileName $N } | Should -Not -Throw
        }
    }
    It 'rejects drive roots, percent expansion and non ASCII paths' {
        InModuleScope tandem-claude-desktop {
            { Resolve-ProfileRoot 'C:\' } | Should -Throw '*drive root*'
            { Resolve-ProfileRoot 'C:\100%\profiles' } | Should -Throw "*'%'*"
            { Resolve-ProfileRoot ('C:\Jos' + [char]0xE9) } | Should -Throw '*non-ASCII*'
        }
    }
    It 'builds separate data and code config paths and safely quotes spaces and ampersands' {
        InModuleScope tandem-claude-desktop {
            $layout = Get-ProfileLayout work 'C:\P & Q'
            $layout.UserData | Should -Be 'C:\P & Q\work\electron'
            $layout.CodeHome | Should -Be 'C:\P & Q\work\claude-code'
            Get-LaunchScriptLine $layout 'C:\Program Files\Claude\app\claude.exe' | Should -Be @(
                '@echo off'
                'set "CLAUDE_CONFIG_DIR=C:\P & Q\work\claude-code"'
                'start "" "C:\Program Files\Claude\app\claude.exe" --user-data-dir="C:\P & Q\work\electron"'
            )
        }
    }
    It 'rejects a linked ancestor' {
        $real = New-Item -ItemType Directory -Path "$TestDrive\real"
        $null = New-Item -ItemType Junction -Path "$TestDrive\link" -Target $real.FullName
        InModuleScope tandem-claude-desktop -Parameters @{ P = "$TestDrive\link\profiles" } {
            param($P)
            { Resolve-ProfileRoot $P } | Should -Throw '*linked profile path*'
        }
    }
}

Describe 'Isolation verification' {
    BeforeEach {
        Mock -ModuleName tandem-claude-desktop Get-CimInstance {
            @(
                [pscustomobject]@{ ProcessId = 1; ParentProcessId = 0; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = '"C:\Pkg\app\claude.exe" --user-data-dir="C:\P\work\electron"' }
                [pscustomobject]@{ ProcessId = 2; ParentProcessId = 1; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = '"C:\Pkg\app\claude.exe" --type=gpu-process --user-data-dir="C:\P\work\electron"' }
                [pscustomobject]@{ ProcessId = 3; ParentProcessId = 0; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = '"C:\Pkg\app\claude.exe"' }
                [pscustomobject]@{ ProcessId = 4; ParentProcessId = 3; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = '"C:\Pkg\app\claude.exe" --type=renderer --user-data-dir="C:\Main"' }
            )
        }
    }
    It 'requires children using the selected data directory and ignores the main account' {
        InModuleScope tandem-claude-desktop {
            Test-ProfileIsolation (Get-ProfileLayout work 'C:\P') | Should -BeTrue
            Test-ProfileIsolation (Get-ProfileLayout work2 'C:\P') | Should -BeFalse
            @(Get-ClaudeMainProcess).ProcessId | Should -Be @(1, 3)
        }
    }
    It 'does not accept requested arguments on a parent without children' {
        Mock -ModuleName tandem-claude-desktop Get-CimInstance {
            [pscustomobject]@{ ProcessId = 1; ParentProcessId = 0; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = 'claude.exe --user-data-dir="C:\P\work\electron"' }
        }
        InModuleScope tandem-claude-desktop { Test-ProfileIsolation (Get-ProfileLayout work 'C:\P') | Should -BeFalse }
    }
    It 'rejects a child falling back to another data directory' {
        Mock -ModuleName tandem-claude-desktop Get-CimInstance {
            @(
                [pscustomobject]@{ ProcessId = 1; ParentProcessId = 0; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = 'claude.exe --user-data-dir="C:\P\work\electron"' }
                [pscustomobject]@{ ProcessId = 2; ParentProcessId = 1; ExecutablePath = 'C:\Pkg\app\claude.exe'; CommandLine = 'claude.exe --type=renderer --user-data-dir="C:\Main"' }
            )
        }
        InModuleScope tandem-claude-desktop { Test-ProfileIsolation (Get-ProfileLayout work 'C:\P') | Should -BeFalse }
    }
    It 'does not match adjacent profile names' {
        InModuleScope tandem-claude-desktop {
            $processes = @([pscustomobject]@{ CommandLine = 'claude.exe --user-data-dir="C:\P\work2\electron"' })
            @(Get-ProfileProcess (Get-ProfileLayout work 'C:\P') -Process $processes).Count | Should -Be 0
        }
    }
    It 'excludes standalone Claude Code binaries' {
        Mock -ModuleName tandem-claude-desktop Get-CimInstance {
            [pscustomobject]@{ ProcessId = 1; ExecutablePath = 'C:\bin\claude.exe'; CommandLine = 'claude.exe --user-data-dir="C:\P\work\electron"' }
        }
        InModuleScope tandem-claude-desktop { @(Get-ClaudeMainProcess).Count | Should -Be 0 }
    }
}

Describe 'Launch verification and cleanup' {
    BeforeEach {
        $root = Join-Path $TestDrive 'profiles'
        New-TestProfile $root
        Mock -ModuleName tandem-claude-desktop Get-ClaudePackage {
            [pscustomobject]@{ Version = '3.1623.1.0'; FamilyName = 'Claude_test'; Exe = 'C:\Pkg\app\claude.exe' }
        }
        Mock -ModuleName tandem-claude-desktop Get-ProfileProcess { }
        Mock -ModuleName tandem-claude-desktop Invoke-InPackage { }
        Mock -ModuleName tandem-claude-desktop Close-ProfileProcess { 1 }
        Mock -ModuleName tandem-claude-desktop Test-ProfileIsolation { $true }
        Mock -ModuleName tandem-claude-desktop Test-FreshWrite { $true }
    }
    It 'rejects missing profiles before starting the app' {
        { Start-ClaudeProfile missing -Root $root } | Should -Throw '*does not exist*'
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-InPackage -Times 0
    }
    It 'verifies both live child paths and app writes' {
        (Start-ClaudeProfile work -Root $root).Status | Should -Be 'Started'
        Should -Invoke -ModuleName tandem-claude-desktop Test-ProfileIsolation -Times 1 -Exactly
        Should -Invoke -ModuleName tandem-claude-desktop Test-FreshWrite -Times 1 -Exactly -ParameterFilter { $Path -like '*\work\electron' }
        Should -Invoke -ModuleName tandem-claude-desktop Close-ProfileProcess -Times 0
        Get-Content "$root\work\launch.cmd" | Should -Contain ('start "" "C:\Pkg\app\claude.exe" --user-data-dir="' + $root + '\work\electron"')
        Test-Path "$root\work\claude-code\auth.json" | Should -BeFalse
    }
    It 'closes only the target when app paths fail verification' {
        Mock -ModuleName tandem-claude-desktop Test-ProfileIsolation { $false }
        { Start-ClaudeProfile work -Root $root -VerifySeconds 1 } | Should -Throw '*did not start using*'
        Should -Invoke -ModuleName tandem-claude-desktop Close-ProfileProcess -Times 1 -Exactly -ParameterFilter { $Layout.Name -eq 'work' }
    }
    It 'closes the target if fresh writes never arrive' {
        Mock -ModuleName tandem-claude-desktop Test-FreshWrite { $false }
        { Start-ClaudeProfile work -Root $root -VerifySeconds 1 } | Should -Throw '*did not start using*'
        Should -Invoke -ModuleName tandem-claude-desktop Close-ProfileProcess -Times 1 -Exactly
    }
    It 'reuses a verified running instance' {
        Mock -ModuleName tandem-claude-desktop Get-ProfileProcess { [pscustomobject]@{ ProcessId = 42 } }
        (Start-ClaudeProfile work -Root $root).Status | Should -Be 'AlreadyRunning'
        Should -Invoke -ModuleName tandem-claude-desktop Test-FreshWrite -Times 0
    }
    It 'honors WhatIf without starting the app' {
        Start-ClaudeProfile work -Root $root -WhatIf
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-InPackage -Times 0
    }
}

Describe 'Profile data lifecycle' {
    BeforeEach {
        $root = Join-Path $TestDrive 'profiles'
        New-TestProfile $root
        Mock -ModuleName tandem-claude-desktop Get-ClaudeMainProcess { }
        Mock -ModuleName tandem-claude-desktop Close-ProfileProcess { }
    }
    It 'lists profile status without reading login files' {
        $p = Get-ClaudeProfile -Root $root
        $p.Name | Should -Be 'work'
        $p.Running | Should -BeFalse
        $p.Login | Should -Be 'Sign in within Claude'
    }
    It 'keeps user data when requested' {
        'keep' | Set-Content "$root\work\electron\sentinel"
        Remove-ClaudeProfile work -Root $root -KeepData -Confirm:$false
        Get-Content "$root\work\electron\sentinel" | Should -Be 'keep'
    }
    It 'removes the selected profile without following nested junctions' {
        $outside = New-Item -ItemType Directory -Path "$TestDrive\outside"
        'keep' | Set-Content "$outside\sentinel"
        $null = New-Item -ItemType Junction -Path "$root\work\electron\linked" -Target $outside.FullName
        Remove-ClaudeProfile work -Root $root -Confirm:$false
        Test-Path "$root\work" | Should -BeFalse
        Get-Content "$outside\sentinel" | Should -Be 'keep'
    }
    It 'refuses to delete outside the explicit root' {
        InModuleScope tandem-claude-desktop -Parameters @{ P = $root; B = "$TestDrive\other" } {
            param($P, $B)
            { Remove-ProfileTree -Path $P -Boundary $B } | Should -Throw '*outside profile root*'
        }
        Test-Path "$root\work" | Should -BeTrue
    }
    It 'does not alter existing code settings when initializing' {
        'custom' | Set-Content "$root\work\claude-code\settings.json"
        InModuleScope tandem-claude-desktop -Parameters @{ R = $root } {
            param($R)
            Initialize-ProfileFolder (Get-ProfileLayout work $R)
        }
        Get-Content "$root\work\claude-code\settings.json" | Should -Be 'custom'
    }
}

Describe 'Claude icon contrast' {
    It 'keeps the light star visible when recoloring the opaque tile' {
        InModuleScope tandem-claude-desktop {
            $bitmap = New-Object System.Drawing.Bitmap 100, 100
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.Clear([System.Drawing.Color]::FromArgb(217, 118, 86))
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(250, 239, 229))
            $graphics.FillRectangle($brush, 40, 40, 20, 20)
            $graphics.Dispose()
            $brush.Dispose()
            try { $png = ConvertTo-TintedPng -Base $bitmap -Size 100 -ColorHex '#1C7ED6' }
            finally { $bitmap.Dispose() }
            $stream = New-Object IO.MemoryStream (, $png)
            $rendered = New-Object System.Drawing.Bitmap $stream
            try {
                $tile = $rendered.GetPixel(10, 50)
                $star = $rendered.GetPixel(50, 50)
                [Math]::Abs($tile.B - 214) | Should -BeLessThan 3
                [Math]::Abs($tile.R - 28) | Should -BeLessThan 3
                $star.R | Should -BeGreaterThan 240
                $star.G | Should -BeGreaterThan 230
            } finally { $rendered.Dispose(); $stream.Dispose() }
        }
    }
}

Describe 'Profile login callback routing' {
    BeforeEach {
        Mock -ModuleName tandem-claude-desktop Get-ProfileSignInState {
            [pscustomobject]@{ id = 'test-registration'; name = 'work'; root = 'C:\P'; expires = [datetime]::UtcNow.AddMinutes(5).ToString('o') }
        }
        Mock -ModuleName tandem-claude-desktop Get-ClaudePackage {
            [pscustomobject]@{ FamilyName = 'Claude_test'; Exe = 'C:\Pkg\app\claude.exe' }
        }
        Mock -ModuleName tandem-claude-desktop Test-ProfileIsolation { $true }
        Mock -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage { }
        Mock -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute { }
        Mock -ModuleName tandem-claude-desktop Write-ProfileLog { }
    }
    It 'forwards Google callbacks unchanged to the selected running profile' {
        InModuleScope tandem-claude-desktop {
            Invoke-ProfileSignInCallback -RegistrationId test-registration -Uri 'claude://login/google-auth?code=synthetic&hop_nonce=x%26y'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage -Times 1 -Exactly -ParameterFilter {
            $Command -eq 'C:\Pkg\app\claude.exe' -and $PesterBoundParameters.Args -eq '--user-data-dir="C:\P\work\electron" "claude://login/google-auth?code=synthetic&hop_nonce=x%26y"'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute -Times 1 -Exactly
        Should -Invoke -ModuleName tandem-claude-desktop Write-ProfileLog -Times 0 -ParameterFilter { $Message -match 'synthetic|hop_nonce' }
    }
    It 'supports email and SSO callbacks: <_>' -ForEach @('claude://claude.ai/magic-link#synthetic:code', 'claude://claude.ai/sso-callback?code=synthetic') {
        InModuleScope tandem-claude-desktop -Parameters @{ Link = $_ } {
            param($Link)
            Invoke-ProfileSignInCallback -RegistrationId test-registration -Uri $Link
        }
        Should -Invoke -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute -Times 1 -Exactly
    }
    It 'rejects invalid links: <_>' -ForEach @('https://example.com/', 'claude://login/google-auth?code="bad"', 'claude://user@login/google-auth', 'claude://login:123/google-auth') {
        InModuleScope tandem-claude-desktop -Parameters @{ Link = $_ } {
            param($Link)
            { Invoke-ProfileSignInCallback -RegistrationId test-registration -Uri $Link } | Should -Throw '*Invalid Claude callback*'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage -Times 0
    }
    It 'leaves unrelated Claude links directed to the main app' {
        InModuleScope tandem-claude-desktop { Invoke-ProfileSignInCallback -RegistrationId test-registration -Uri 'claude://claude.ai/settings' }
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.Args -eq '"claude://claude.ai/settings"'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute -Times 0
    }
    It 'requires a running isolated target and still restores link handling on failure' {
        Mock -ModuleName tandem-claude-desktop Test-ProfileIsolation { $false }
        InModuleScope tandem-claude-desktop {
            { Invoke-ProfileSignInCallback -RegistrationId test-registration -Uri 'claude://login/google-auth?code=synthetic' } | Should -Throw '*must be running*'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage -Times 0
        Should -Invoke -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute -Times 1 -Exactly
    }
    It 'rejects callbacks for a replaced registration' {
        InModuleScope tandem-claude-desktop {
            { Invoke-ProfileSignInCallback -RegistrationId previous-registration -Uri 'claude://login/google-auth?code=synthetic' } | Should -Throw '*expired*'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage -Times 0
        Should -Invoke -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute -Times 0
    }
    It 'cleans up an expired registration without forwarding a callback' {
        Mock -ModuleName tandem-claude-desktop Get-ProfileSignInState {
            [pscustomobject]@{ id = 'test-registration'; expires = [datetime]::UtcNow.AddMinutes(-1).ToString('o') }
        }
        InModuleScope tandem-claude-desktop {
            { Invoke-ProfileSignInCallback -RegistrationId test-registration -Uri 'claude://login/google-auth?code=synthetic' } | Should -Throw '*expired*'
        }
        Should -Invoke -ModuleName tandem-claude-desktop Remove-ProfileSignInRoute -Times 1 -Exactly
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-CommandInDesktopPackage -Times 0
    }
}

Describe 'Protocol registration restoration' {
    It 'restores original command presence and delegate: <CommandExisted>' -ForEach @(
        @{ CommandExisted = $false }, @{ CommandExisted = $true }
    ) {
        InModuleScope tandem-claude-desktop -Parameters @{ Present = $CommandExisted; Temp = $TestDrive } {
            param($Present, $Temp)
            Initialize-ProfileAssociationApi
            $registryBase = 'Software\Classes\AppXTandemTest' + [guid]::NewGuid().ToString('N')
            $commandPath = $registryBase + '\Shell\open\command'
            if ($null -ne [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($registryBase)) { throw 'Test key already exists' }
            $testKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($commandPath)
            $script:RoutingTestStatePath = Join-Path $Temp 'test-signin.json'
            '{}' | Set-Content -LiteralPath $script:RoutingTestStatePath
            $script:RoutingTestState = [pscustomobject]@{
                id = 'synthetic-registration'; commandKey = $commandPath
                commandExisted = $Present; commandValue = $(if ($Present) { 'original command' } else { $null })
                delegateExisted = $true; delegateValue = '{original-delegate}'
            }
            Mock Get-ProfileSignInState { $script:RoutingTestState }
            Mock Get-ProfileSignInStatePath { $script:RoutingTestStatePath }
            try {
                $testKey.SetValue('', 'temporary synthetic-registration command')
                $testKey.SetValue('DelegateExecute', '')
                $testKey.SetValue('UnrelatedValue', 'keep')
                Remove-ProfileSignInRoute -RegistrationId synthetic-registration
                ($testKey.GetValueNames() -contains '') | Should -Be $Present
                if ($Present) { $testKey.GetValue('') | Should -Be 'original command' }
                $testKey.GetValue('DelegateExecute') | Should -Be '{original-delegate}'
                $testKey.GetValue('UnrelatedValue') | Should -Be 'keep'
                Test-Path -LiteralPath $script:RoutingTestStatePath | Should -BeFalse
            } finally {
                $testKey.Dispose()
                [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($registryBase)
            }
        }
    }
}

Describe 'Sequential handoff launcher guards' {
    BeforeEach {
        $switchRoot = Join-Path $TestDrive 'switching'
        $null = New-Item -ItemType Directory -Path $switchRoot -Force
        Mock -ModuleName tandem-claude-desktop Invoke-SessionHandoffHelper {
            [pscustomobject]@{ source = 'main'; target = 'work'; sessions = 1 }
        }
        Mock -ModuleName tandem-claude-desktop Get-ClaudePackage {
            [pscustomobject]@{ FamilyName = 'Claude_test'; Exe = 'C:\Pkg\app\claude.exe' }
        }
        Mock -ModuleName tandem-claude-desktop Get-ClaudeMainProcess { }
        Mock -ModuleName tandem-claude-desktop Stop-Process { }
        Mock -ModuleName tandem-claude-desktop Get-CimInstance { }
    }
    It 'previews without stopping a window or publishing history' {
        (Switch-ClaudeProfile work -Root $switchRoot -Preview).sessions | Should -Be 1
        Should -Invoke -ModuleName tandem-claude-desktop Stop-Process -Times 0
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-SessionHandoffHelper -Times 0 -ParameterFilter { -not $Preview }
    }
    It 'refuses to stop windows when a Code backend is still open' {
        Mock -ModuleName tandem-claude-desktop Get-CimInstance {
            [pscustomobject]@{ ExecutablePath = 'C:\Code\claude.exe'; CommandLine = 'claude.exe --resume synthetic' }
        }
        { Switch-ClaudeProfile work -Root $switchRoot } | Should -Throw '*still open*no windows were stopped*'
        Should -Invoke -ModuleName tandem-claude-desktop Stop-Process -Times 0
        Should -Invoke -ModuleName tandem-claude-desktop Invoke-SessionHandoffHelper -Times 0 -ParameterFilter { -not $Preview }
    }
}
