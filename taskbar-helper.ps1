#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'tandem-claude-desktop') -Force -PassThru
$rootPath = & $module { param($R) Resolve-ProfileRoot $R } $Root
$identity = & $module { param($R) Get-TaskbarAppId -Root $R -Name main } $rootPath
$mutex = New-Object Threading.Mutex($false, ('Local\' + $identity))
$owned = $false
$statePath = Join-Path $rootPath 'taskbar-helper.json'
$stopPath = Join-Path $rootPath 'taskbar-stop'
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { exit 0 }
    & $module { Initialize-TaskbarApi }
    if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath -Force }
    @{ pid = $PID } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    $idleSince = Get-Date
    $problems = @{}
    while (-not (Test-Path -LiteralPath $stopPath)) {
        try {
            $profiles = @(& $module { param($R) Get-TaskbarProfile -Root $R } $rootPath)
            $processes = @(& $module { Get-ClaudeMainProcess })
        } catch {
            if ($problems['discovery'] -ne $_.Exception.Message) {
                Add-Content -LiteralPath (Join-Path $rootPath 'taskbar.log') -Value ((Get-Date).ToString('s') + ' ' + $_.Exception.Message)
                $problems['discovery'] = $_.Exception.Message
            }
            Start-Sleep -Seconds 2
            continue
        }
        $managed = 0
        foreach ($process in $processes) {
            $match = [regex]::Match($process.CommandLine, '--user-data-dir=(?:"(?<path>[^"]+)"|(?<path>\S+))')
            $data = Join-Path $env:APPDATA 'Claude'
            if ($match.Success) { $data = [IO.Path]::GetFullPath($match.Groups['path'].Value).TrimEnd('\') }
            $matchedProfile = $profiles | Where-Object { $_.UserData -eq $data } | Select-Object -First 1
            if ($null -eq $matchedProfile) { continue }
            $managed++
            foreach ($window in [Tandem.Claude.TaskbarIdentity]::WindowsForProcess([uint32]$process.ProcessId)) {
                try {
                    if ([Tandem.Claude.TaskbarIdentity]::NeedsApply($window, $matchedProfile.AppId, $matchedProfile.Icon)) {
                        [Tandem.Claude.TaskbarIdentity]::Apply($window, $matchedProfile.AppId, $matchedProfile.Command, $matchedProfile.Label, $matchedProfile.Icon)
                    }
                } catch {
                    if ($problems[$window] -ne $_.Exception.Message) {
                        Add-Content -LiteralPath (Join-Path $rootPath 'taskbar.log') -Value ((Get-Date).ToString('s') + ' ' + $_.Exception.Message)
                        $problems[$window] = $_.Exception.Message
                    }
                }
            }
        }
        if ($managed) { $idleSince = Get-Date }
        elseif (((Get-Date) - $idleSince).TotalSeconds -ge 30) { break }
        Start-Sleep -Seconds 2
    }
} catch {
    Add-Content -LiteralPath (Join-Path $rootPath 'taskbar.log') -Value ((Get-Date).ToString('s') + ' ' + $_.Exception.Message)
} finally {
    if ($owned) {
        if ('Tandem.Claude.TaskbarIdentity' -as [type]) { [Tandem.Claude.TaskbarIdentity]::RestoreAll() }
        Remove-Item -LiteralPath $statePath, $stopPath -Force -ErrorAction SilentlyContinue
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
