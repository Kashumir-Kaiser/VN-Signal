# Local, offline database follow-up. Wait for the identified feature run; never
# compete with it or silently execute a changed migration/test tree.
$ErrorActionPreference='Stop'
Set-Location -LiteralPath 'C:\Users\HP\VN-Signal'
$root=$PWD.Path
$prefix=Join-Path $root 'docs/evidence/phase2/phase2_serial_followup_078_scheduler_retry_20261024'
$state=[ordered]@{pid=$PID;process_started_utc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');phase='waiting_for_features';exit_code=$null;updated_utc=$null}
function Save-State {
 $state.updated_utc=[datetime]::UtcNow.ToString('o')
 [IO.File]::WriteAllText($prefix+'.status.json.tmp',($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 [IO.File]::Move($prefix+'.status.json.tmp',$prefix+'.status.json',$true)
}
function Check-Exit([string]$step) { if($LASTEXITCODE -ne 0){throw "$step failed with exit $LASTEXITCODE"} }
$result=1
try {
 $files=@(Get-ChildItem sql/migrations,tests/sql -File -Recurse) + @(Get-Item py/vnstock_worker.py,docs/evidence/phase2/phase2_vci_lineage_full_077_20261024.sql,docs/evidence/phase2/phase2_public_execution_full_082_20261024.sql)
 $expected=@($files | ForEach-Object { [ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
 $expected|ConvertTo-Json -Depth 3|Set-Content -LiteralPath ($prefix+'.inputs.json')
 Save-State
 while($true) {
  $build=Get-Content -Raw docs/evidence/phase2/phase2_v3_078_scheduler_resume4_20261024.status.json|ConvertFrom-Json
  if($build.build_id -ne 'phase2-v3-074-clean-full-20261024'){throw 'feature build identity changed'}
  if($build.phase -eq 'completed' -and $build.exit_code -eq 0){break}
  if($build.phase -ne 'running'){throw "feature run terminal without success: $($build.phase)"}
  $process=Get-Process -Id $build.pid -ErrorAction SilentlyContinue
  if(-not $process -or ([datetime]$build.process_started_utc).ToUniversalTime().Ticks -ne $process.StartTime.ToUniversalTime().Ticks){throw 'identified feature process disappeared without terminal success'}
  Start-Sleep -Seconds 30
 }
 foreach($entry in $expected){if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ne $entry.sha256){throw "queued input changed: $($entry.path)"}}
 $currentFiles=@(Get-ChildItem sql/migrations,tests/sql -File -Recurse) + @(Get-Item py/vnstock_worker.py,docs/evidence/phase2/phase2_vci_lineage_full_077_20261024.sql,docs/evidence/phase2/phase2_public_execution_full_082_20261024.sql)
 if($currentFiles.Count -ne $expected.Count){throw 'queued migration/test file set changed'}
 $credential=Import-Clixml -LiteralPath "C:\Users\HP\VN-Signal\.phase2-runtime\db-credential.xml"
 $env:PGPASSWORD=$credential.GetNetworkCredential().Password
 $env:PATH='C:\Program Files\PostgreSQL\18\bin;'+$env:PATH
 $env:VNPIPE_DISABLE_LIVE='1'
 $state.phase='migration_harness';Save-State
 $env:DATABASE_URL='postgresql://postgres@localhost:5432/vnsignal_phase2_078_serial_20261024_disposable'
 $env:VNPIPE_TEST_DATABASE_NAME='vnsignal_phase2_078_serial_20261024_disposable'
 & 'C:\Program Files\PostgreSQL\18\bin\createdb.exe' -U postgres $env:VNPIPE_TEST_DATABASE_NAME *> ($prefix+'.createdb.log')
 Check-Exit 'fresh disposable database creation'
 & 'C:\Program Files\Git\bin\bash.exe' tests/sql/test_migration.sh *> ($prefix+'.harness.log')
 Check-Exit 'fresh two-pass migration harness'
 $state.phase='apply_report_migration';Save-State
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f sql/migrations/077_phase2_recovered_vci_lineage.sql *> ($prefix+'.apply.log')
 Check-Exit 'report migration077'
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f sql/migrations/078_phase2_fundamental_v3_cohort.sql *> ($prefix+'.apply078.log')
 Check-Exit 'report migration078'
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f sql/migrations/079_phase2_parent_valuation.sql *> ($prefix+'.apply079.log')
 Check-Exit 'report migration079'
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f sql/migrations/080_phase2_listing_tenure.sql *> ($prefix+'.apply080.log')
 Check-Exit 'report migration080'
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f sql/migrations/081_phase2_industry_availability.sql *> ($prefix+'.apply081.log')
 Check-Exit 'report migration081'
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f sql/migrations/082_phase2_public_execution_tenure.sql *> ($prefix+'.apply082.log')
 Check-Exit 'report migration082'
 $state.phase='public_execution_archive';Save-State
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f docs/evidence/phase2/phase2_public_execution_full_082_20261024.sql *> ($prefix+'.public_execution.log')
 Check-Exit 'full exact public execution archive'
 $state.phase='lineage_archive';Save-State
 & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -X -v ON_ERROR_STOP=1 -U postgres -d vnsignal_phase2_report_20261019 -f docs/evidence/phase2/phase2_vci_lineage_full_077_20261024.sql *> ($prefix+'.lineage.log')
 Check-Exit 'full recovered-source lineage archive'
 $result=0;$state.phase='completed'
} catch {
 $_.Exception.Message|Add-Content -LiteralPath ($prefix+'.error.log')
 $state.phase='failed'
} finally {
 Remove-Item Env:PGPASSWORD,Env:DATABASE_URL -ErrorAction SilentlyContinue
 $state.exit_code=$result;Save-State
}
exit $result

