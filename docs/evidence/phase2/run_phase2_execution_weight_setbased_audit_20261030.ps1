[CmdletBinding()]
param(
    [string]$DatabaseName = 'vnsignal_phase2_report_20261019',
    [string]$DateFrom = '2018-10-01',
    [string]$DateTo = '2026-10-16',
    [switch]$RerunSuccessful,
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
)

$ErrorActionPreference = 'Stop'

if ($DatabaseName -cne 'vnsignal_phase2_report_20261019') {
    throw 'This evidence runner is restricted to vnsignal_phase2_report_20261019.'
}
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    throw 'Set PGPASSWORD in the current PowerShell process before running this evidence check.'
}
if (-not (Test-Path -LiteralPath $PsqlPath -PathType Leaf)) {
    throw "psql executable not found: $PsqlPath"
}

$fromDate = [DateTime]::ParseExact($DateFrom,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
$toDate = [DateTime]::ParseExact($DateTo,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
if ($fromDate -gt $toDate) { throw 'DateFrom must be on or before DateTo.' }

$sqlPath = Join-Path $PSScriptRoot 'phase2_execution_weight_setbased_audit_20261030.sql'
$sqlHash = (Get-FileHash -LiteralPath $sqlPath -Algorithm SHA256).Hash.ToLowerInvariant()
$stopFlag = Join-Path $PSScriptRoot 'phase2_execution_weight_audit.stop'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'

Write-Host "AUDIT target=$DatabaseName range=$DateFrom..$DateTo batch=calendar-quarter work_mem=8MB"
Write-Host "AUDIT SQL SHA-256=$sqlHash"

$cursor = $fromDate
while ($cursor -le $toDate) {
    $quarterStartMonth = [int]([Math]::Floor(($cursor.Month - 1) / 3) * 3 + 1)
    $quarterStart = [DateTime]::new($cursor.Year,$quarterStartMonth,1)
    $quarterEnd = $quarterStart.AddMonths(3).AddDays(-1)
    $batchFrom = if ($cursor -gt $fromDate) { $cursor } else { $fromDate }
    $batchTo = if ($quarterEnd -lt $toDate) { $quarterEnd } else { $toDate }
    $fromText = $batchFrom.ToString('yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    $toText = $batchTo.ToString('yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    $rangeToken = $batchFrom.ToString('yyyyMMdd') + '_' + $batchTo.ToString('yyyyMMdd')

    $successfulStatus = $false
    if (-not $RerunSuccessful) {
        $priorStatuses = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "phase2_execution_weight_setbased_audit_${rangeToken}_*.status.json" -File -ErrorAction SilentlyContinue
        foreach ($prior in $priorStatuses) {
            try {
                $state = Get-Content -LiteralPath $prior.FullName -Raw | ConvertFrom-Json
                if ($state.exit_code -eq 0 -and $state.sql_sha256 -eq $sqlHash -and
                    $state.date_from -eq $fromText -and $state.date_to -eq $toText) {
                    $successfulStatus = $true
                    Write-Host "SKIP audited $fromText..$toText; successful evidence $($prior.Name)"
                    break
                }
            }
            catch {
                Write-Host "IGNORE unreadable prior status $($prior.Name)"
            }
        }
    }
    else {
        Write-Host "RERUN requested for $fromText..$toText despite prior successful evidence"
    }
    if ($successfulStatus) {
        $cursor = $batchTo.AddDays(1)
        continue
    }

    $logPath = Join-Path $PSScriptRoot "phase2_execution_weight_setbased_audit_${rangeToken}_${runStamp}.log"
    $statusPath = [IO.Path]::ChangeExtension($logPath,'.status.json')
    @(
        "Target database: $DatabaseName"
        "Date range: $fromText through $toText"
        "Batch: calendar-aligned quarter"
        "SQL SHA-256: $sqlHash"
        "Started at: $([DateTimeOffset]::Now.ToString('o'))"
        'Database scope: temporary staging tables only; final ROLLBACK'
        ''
    ) | Set-Content -LiteralPath $logPath -Encoding UTF8
    Write-Host "START audit $fromText..$toText"

    & $PsqlPath -X -q -w -h 127.0.0.1 -U postgres -d $DatabaseName `
        -v ON_ERROR_STOP=1 -v "date_from=$fromText" -v "date_to=$toText" `
        -f $sqlPath 2>&1 | Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE
    $status = [ordered]@{
        database = $DatabaseName
        date_from = $fromText
        date_to = $toText
        sql_sha256 = $sqlHash
        exit_code = $exitCode
        completed_at = [DateTimeOffset]::Now.ToString('o')
        log = [IO.Path]::GetFileName($logPath)
    }
    $status | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statusPath -Encoding UTF8
    if ($exitCode -ne 0) {
        Write-Host "FAILED audit $fromText..$toText exit=$exitCode; partial work was rolled back."
        throw "Execution-weight audit stopped after failed range $fromText through $toText. Resume by rerunning this script."
    }

    Write-Host "DONE audit $fromText..$toText log=$([IO.Path]::GetFileName($logPath))"
    $cursor = $batchTo.AddDays(1)
    if (Test-Path -LiteralPath $stopFlag -PathType Leaf) {
        Write-Host "SAFE_STOP after committed read-only batch $fromText..$toText; remove $stopFlag to resume."
        break
    }
}

Write-Host 'AUDIT runner finished its requested range.'
