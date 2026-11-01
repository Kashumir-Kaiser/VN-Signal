$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:DATABASE_URL)) {
    throw 'Set DATABASE_URL to the disposable report database before running E2.'
}
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sqlFile = Join-Path $repositoryRoot 'tests/sql/phase2_e2_real_assertions.sql'
$evidenceDirectory = Join-Path $repositoryRoot 'docs/evidence/phase2'
$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$evidenceFile = Join-Path $evidenceDirectory "phase2_e2_real_$runStamp.txt"
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null

$databaseName = & psql -X -v ON_ERROR_STOP=1 -Atqc 'SELECT current_database()' $env:DATABASE_URL
if ($LASTEXITCODE -ne 0) { throw 'Could not identify the selected PostgreSQL database.' }
if ($databaseName.Trim() -cne 'vnsignal_phase2_report_20261019') {
    throw "Refusing E2: expected vnsignal_phase2_report_20261019, connected to '$($databaseName.Trim())'."
}

# Keep the report-clone sort memory at PostgreSQL's measured 4 MB setting;
# the earlier 32 MB override made the adjustment-view snapshot substantially slower.
$env:PGOPTIONS = '-c TimeZone=UTC -c statement_timeout=1800000 -c lock_timeout=5000 -c work_mem=4MB -c jit=off'
& psql -X -v ON_ERROR_STOP=1 -f $sqlFile $env:DATABASE_URL 2>&1 | Tee-Object -FilePath $evidenceFile
if ($LASTEXITCODE -ne 0) { throw "Real-data E2 failed; inspect $evidenceFile" }
Write-Output "Real-data E2 completed. Evidence: $evidenceFile"
