# Local operational launcher: no credentials are stored in this artifact.
$ErrorActionPreference='Stop'
Set-Location -LiteralPath 'C:\Users\HP\VN-Signal'
$logPath='C:\Users\HP\VN-Signal\docs\evidence\phase2\phase2_v3_074_clean_full_resume1_20261024.log'
$statusPath='C:\Users\HP\VN-Signal\docs\evidence\phase2\phase2_v3_074_clean_full_resume1_20261024.status.json'
$state=[ordered]@{
 build_id='phase2-v3-074-clean-full-20261024'
 pid=$PID
 process_started_utc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
 started_utc=[datetime]::UtcNow.ToString('o')
 phase='running'
 exit_code=$null
}
function Save-State {
 $temporary=$statusPath+'.tmp'
 [IO.File]::WriteAllText($temporary,($state | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 [IO.File]::Move($temporary,$statusPath,$true)
}
Save-State
$result=1
try {
 $credential=Import-Clixml -LiteralPath "$env:LOCALAPPDATA\VN-Signal\db-credential.xml"
 $env:PGPASSWORD=$credential.GetNetworkCredential().Password
 & ./ops/phase2_build.ps1 -DatabaseUrl 'postgresql://postgres@localhost:5432/vnsignal_phase2_report_20261019' -BuildId $state.build_id -Stage features -ChunkMonths 3 -SymbolBatchSize 15 -WorkMem 8MB -MaintenanceWorkMem 16MB -StatementTimeoutMinutes 30 -PsqlPath 'C:\Program Files\PostgreSQL\18\bin\psql.exe' *> $logPath
 if($LASTEXITCODE -ne 0){throw "Runner native command exited $LASTEXITCODE"}
 $result=0
} catch {
 $_ | Out-String | Add-Content -LiteralPath $logPath
} finally {
 Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
 $state.phase=if($result -eq 0){'completed'}else{'failed'}
 $state.exit_code=$result
 $state.finished_utc=[datetime]::UtcNow.ToString('o')
 Save-State
}
exit $result
