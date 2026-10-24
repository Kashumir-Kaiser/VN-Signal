[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$refreshScript = Join-Path $PSScriptRoot 'daily-market-refresh.ps1'
$credentialPath = Join-Path (Join-Path $env:LOCALAPPDATA 'VN-Signal') 'db-credential.xml'
if (-not (Test-Path -LiteralPath $refreshScript -PathType Leaf)) {
    throw "Refresh script is missing at $refreshScript"
}
if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
    throw 'Run save-db-credential.ps1 once before installing the scheduled task.'
}

$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw "Windows PowerShell is missing at $powerShell"
}
$actionArgs = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $refreshScript + '"'
$action = New-ScheduledTaskAction -Execute $powerShell -Argument $actionArgs -WorkingDirectory $repoRoot
$trigger = New-ScheduledTaskTrigger -Daily -At '6:00 AM'
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settingsArgs = @{
    StartWhenAvailable = $true
    WakeToRun = $true
    AllowStartIfOnBatteries = $true
    DontStopIfGoingOnBatteries = $true
    MultipleInstances = 'IgnoreNew'
    ExecutionTimeLimit = (New-TimeSpan -Hours 5)
    RestartCount = 2
    RestartInterval = (New-TimeSpan -Minutes 15)
}
$settings = New-ScheduledTaskSettingsSet @settingsArgs

Register-ScheduledTask -TaskName 'VN-Signal Daily Market Refresh' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Refresh recent VCI canonical bars and source-keyed VNDIRECT history at 6:00 AM local time.' -Force | Out-Null

$task = Get-ScheduledTask -TaskName 'VN-Signal Daily Market Refresh'
$nextRun = (Get-ScheduledTaskInfo -TaskName $task.TaskName).NextRunTime
Write-Output ("Registered {0}: state={1}, user={2}, next run={3}" -f $task.TaskName, $task.State, $userId, $nextRun)
