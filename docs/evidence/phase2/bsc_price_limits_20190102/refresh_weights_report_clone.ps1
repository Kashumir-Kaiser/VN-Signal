param(
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string]$HostName = '127.0.0.1',
    [int]$Port = 5432,
    [string]$User = 'postgres',
    [string]$Database = 'vnsignal_phase2_report_20261019',
    [string]$SignalDateFrom = '2018-12-10',
    [string]$SignalDateTo = '2018-12-18',
    [string]$EvidenceTradeDate = '2019-01-02',
    [int]$BatchSize = 200,
    [string]$LogDate = (Get-Date -Format 'yyyyMMdd')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PsqlPath -PathType Leaf)) {
    throw "psql executable not found: $PsqlPath"
}
if ($Database -cne 'vnsignal_phase2_report_20261019') {
    throw 'BSC weight refresh is restricted to the disposable Phase 2 report clone.'
}
foreach ($date in @($SignalDateFrom,$SignalDateTo,$EvidenceTradeDate)) {
    if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Invalid ISO date: $date" }
}
if ($BatchSize -lt 1 -or $BatchSize -gt 500) {
    throw 'BatchSize must be between 1 and 500.'
}

$baseArgs = @(
    '-X','-w','-v','ON_ERROR_STOP=1',
    '-h',$HostName,'-p',[string]$Port,'-U',$User,'-d',$Database
)
$guard = @'
DO $target_guard$
BEGIN
    IF current_database()<>'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'BSC weight refresh is restricted to the disposable report clone';
    END IF;
END
$target_guard$;
'@
$symbolQuery = @"
SELECT string_agg(symbol_id::text,',' ORDER BY symbol_id)
  FROM (
      SELECT DISTINCT p.symbol_id
        FROM core.daily_price_limit_observations p
        JOIN raw.landings l ON l.landing_id=p.raw_landing_id
       WHERE p.source='bsc' AND p.trade_date=DATE '$EvidenceTradeDate'
         AND l.ingest_id='8b000000-2019-4019-8000-000000000102'::uuid
  ) symbols;
"@
$symbolCsv = & $PsqlPath @baseArgs '-At' '-c' $symbolQuery
if ($LASTEXITCODE -ne 0) { throw 'Could not read BSC symbol IDs from the report clone.' }
$symbolText = [string]$symbolCsv
$symbolIds = @($symbolText.Trim().Split(',') | Where-Object { $_ -match '^\d+$' })
if ($symbolIds.Count -ne 834) {
    throw "Expected 834 BSC symbol IDs for the imported capture; found $($symbolIds.Count)."
}

$batches = [System.Collections.Generic.List[object]]::new()
for ($offset=0; $offset -lt $symbolIds.Count; $offset += $BatchSize) {
    $end = [Math]::Min($offset + $BatchSize,$symbolIds.Count)
    $chunk = @($symbolIds[$offset..($end-1)])
    $batches.Add([pscustomobject]@{
        Number = $batches.Count + 1
        Symbols = $chunk
    })
}

$safeFrom = $SignalDateFrom.Replace('-','')
$safeTo = $SignalDateTo.Replace('-','')
foreach ($batch in $batches) {
    $array = 'ARRAY[' + ($batch.Symbols -join ',') + ']::bigint[]'
    $sql = @"
$guard
SET statement_timeout='10min';
SET lock_timeout='5s';
SELECT feat.refresh_phase2_execution_weights(
    DATE '$SignalDateFrom',DATE '$SignalDateTo',DATE '$EvidenceTradeDate',$array
) AS refreshed_targets;
"@
    $logPath = Join-Path $PSScriptRoot ("weight_refresh_{0}_{1}_{2}_symbols_{3:D2}_{4}.log" -f `
        $safeFrom,$safeTo,$EvidenceTradeDate.Replace('-',''),$batch.Number,$LogDate)
    Write-Output ("Refreshing batch {0}/{1} ({2} symbols) for {3}..{4}." -f `
        $batch.Number,$batches.Count,$batch.Symbols.Count,$SignalDateFrom,$SignalDateTo)
    & $PsqlPath @baseArgs '-c' $sql 2>&1 | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) {
        throw "Batch $($batch.Number) failed. Its log is $logPath; prior batch logs remain committed."
    }
}
Write-Output ("Completed {0} symbol batches ({1} imported BSC symbols)." -f $batches.Count,$symbolIds.Count)
