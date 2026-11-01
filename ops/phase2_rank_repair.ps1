[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DatabaseUrl,
    [ValidateSet('Probe','Repair')][string]$Mode = 'Probe',
    [ValidatePattern('^[A-Za-z0-9._-]{1,100}$')][string]$BuildId = 'phase2-rank-repair-053-20261022',
    [ValidateRange(0,10000)][int]$MaxChunks = 0,
    [string]$StartDate,
    [ValidateRange(1,25)][int]$StatementTimeoutMinutes = 5,
    [ValidateRange(4,128)][int]$WorkMemMegabytes = 16,
    [string]$PsqlPath = 'psql'
)
$ErrorActionPreference = 'Stop'
if ($DatabaseUrl -match '://[^/]*:[^/@]+@') {
    throw 'Keep passwords out of the URL; use PGPASSWORD or the local credential store.'
}
$null = Get-Command $PsqlPath -CommandType Application -ErrorAction Stop
function Sql-Literal([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
function Invoke-Sql([string]$Sql) {
    $previous = $ErrorActionPreference
    $previousOptions = $env:PGOPTIONS
    try {
        # Native stderr must be captured, including errors, before checking the
        # process exit code. PowerShell 5 otherwise throws on native notices.
        $ErrorActionPreference = 'Continue'
        $env:PGOPTIONS = "$previousOptions -c TimeZone=UTC -c statement_timeout=$($StatementTimeoutMinutes*60000) -c work_mem=${WorkMemMegabytes}MB -c effective_io_concurrency=0 -c maintenance_io_concurrency=0 -c max_parallel_workers_per_gather=0 -c jit=off"
        $output = & $PsqlPath -X -qAt -F '|' -v ON_ERROR_STOP=1 -c $Sql $DatabaseUrl 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous; $env:PGOPTIONS = $previousOptions }
    $result = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if ($code -ne 0) { throw "psql exit ${code}: $result" }
    return $result
}
$database = Invoke-Sql 'SELECT current_database()'
if ($database -cne 'vnsignal_phase2_report_20261019') {
    throw "Rank recovery is restricted to vnsignal_phase2_report_20261019; connected to '$database'."
}
$bounds = (Invoke-Sql "SELECT min(trade_date),max(trade_date) FROM feat.features_daily WHERE feature_version='phase2-v2'") -split '\|'
if ($bounds.Count -ne 2 -or $bounds[0] -notmatch '^\d{4}-\d{2}-\d{2}$' -or $bounds[1] -notmatch '^\d{4}-\d{2}-\d{2}$') {
    throw 'The report clone has no valid V2 date bounds.'
}
$culture = [Globalization.CultureInfo]::InvariantCulture
$cursor = [datetime]::ParseExact($bounds[0], 'yyyy-MM-dd', $culture)
$last = [datetime]::ParseExact($bounds[1], 'yyyy-MM-dd', $culture)
if (-not [string]::IsNullOrWhiteSpace($StartDate)) {
    if ($Mode -ne 'Repair' -or $StartDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw 'StartDate is supported only for Repair mode and must use YYYY-MM-DD.'
    }
    $requestedStart = [datetime]::ParseExact($StartDate,'yyyy-MM-dd',$culture)
    if ($requestedStart.Day -ne 1 -or $requestedStart -lt $cursor -or $requestedStart -gt $last) {
        throw 'StartDate must be the first day of an in-range month.'
    }
    $cursor = $requestedStart
}
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\evidence\phase2'))
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$logPath = Join-Path $evidence ("phase2_rank_repair_${BuildId}.log")
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Evidence([string]$Message) {
    [IO.File]::AppendAllText($logPath, $Message + [Environment]::NewLine, $utf8)
    Write-Output $Message
}
Write-Evidence ("Run {0:o}; database={1}; build={2}; mode={3}; dates={4}..{5}; start={6:yyyy-MM-dd}" -f (Get-Date),$database,$BuildId,$Mode,$bounds[0],$bounds[1],$cursor)
$build = Sql-Literal $BuildId
$probePath = Join-Path $evidence ("phase2_rank_probe_${BuildId}.json")
$definition = Invoke-Sql @'
SELECT ops.phase2_hash_text(
    pg_get_functiondef('ops.repair_phase2_rank_chunk(text,date,date,boolean)'::regprocedure)
    ||pg_get_functiondef('feat.phase2_cross_sectional_ranks(date,date,bigint[])'::regprocedure)
    ||pg_get_functiondef('ops.phase2_rank_panel_hash(date,date,boolean)'::regprocedure))
'@
if ($Mode -eq 'Probe') {
    # A failed rerun must not leave an older passing certificate usable.
    [IO.File]::WriteAllText($probePath,('{"passed":false,"state":"running"}'),$utf8)
    $samples = @()
    foreach ($sessions in @(30,60,120)) {
        $probeFrom = Invoke-Sql @"
SELECT trade_date FROM (
    SELECT trade_date,row_number() OVER(ORDER BY trade_date DESC) AS n
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date BETWEEN '$($bounds[0])' AND '$($bounds[1])'
) s WHERE n=$sessions
"@
        if ($probeFrom -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Fewer than $sessions effective sessions in the panel." }
        $samples += [pscustomobject]@{ sessions=$sessions; date_from=$probeFrom; date_to=$bounds[1] }
    }

    # Warm the largest nested date range once, then time only the read-only S2
    # rank stage. Repair-and-rollback probes leave dead tuple versions behind,
    # which contaminates later samples despite their logical rollback.
    $warm = $samples[2]
    $warmSql = @"
BEGIN READ ONLY;
SET LOCAL search_path TO core,feat,ops;
DO `$rank_scale`$
DECLARE n bigint;
BEGIN
    SELECT count(*) INTO n FROM feat.phase2_cross_sectional_ranks('$($warm.date_from)','$($warm.date_to)',NULL::bigint[]);
    RAISE NOTICE 'PHASE2_RANK_WARMUP|sessions=120|rows=%',n;
END `$rank_scale`$;
ROLLBACK;
"@
    try { $warmResult = Invoke-Sql $warmSql }
    catch { Write-Evidence ("PROBE WARMUP FAILED|{0}" -f $_); throw }
    if ($warmResult -notmatch 'PHASE2_RANK_WARMUP\|sessions=120\|rows=\d+') {
        throw "Unexpected rank-stage warm-up result: $warmResult"
    }
    Write-Evidence $warmResult

    $measurements = @()
    foreach ($sample in $samples) {
        $sessions = $sample.sessions
        $trialTimes = @()
        $expectedRows = $null
        for ($trial=1; $trial -le 3; $trial++) {
            $measureSql = @"
BEGIN READ ONLY;
SET LOCAL search_path TO core,feat,ops;
DO `$rank_scale`$
DECLARE started_at timestamptz:=clock_timestamp(); n bigint;
BEGIN
    SELECT count(*) INTO n FROM feat.phase2_cross_sectional_ranks('$($sample.date_from)','$($sample.date_to)',NULL::bigint[]);
    RAISE NOTICE 'PHASE2_RANK_STAGE|sessions=$sessions|trial=$trial|rows=%|seconds=%',
        n,round(extract(epoch FROM clock_timestamp()-started_at)::numeric,6);
END `$rank_scale`$;
ROLLBACK;
"@
            try { $result = Invoke-Sql $measureSql }
            catch { Write-Evidence ("PROBE FAILED sessions={0}|trial={1}|range={2}..{3}|{4}" -f $sessions,$trial,$sample.date_from,$sample.date_to,$_); throw }
            $match = [regex]::Match($result,'PHASE2_RANK_STAGE\|sessions=(\d+)\|trial=(\d+)\|rows=(\d+)\|seconds=([0-9]+(?:\.[0-9]+)?)')
            if (-not $match.Success -or [int]$match.Groups[1].Value -ne $sessions -or
                [int]$match.Groups[2].Value -ne $trial) {
                throw "Unexpected read-only rank-stage result: $result"
            }
            $seconds = [double]::Parse($match.Groups[4].Value,$culture)
            $rankRows = [long]$match.Groups[3].Value
            if ($seconds -le 0 -or $rankRows -le 0) { throw "Invalid rank-stage measurement: $result" }
            if ($null -ne $expectedRows -and $rankRows -ne $expectedRows) {
                throw 'Read-only rank-stage row count changed between timed trials.'
            }
            $expectedRows = $rankRows
            $trialTimes += $seconds
            Write-Evidence ("PROBE rank_stage_trial sessions={0}|trial={1}|rows={2}|seconds={3:F6}|read_only=true" -f $sessions,$trial,$rankRows,$seconds)
        }
        $orderedTimes = @($trialTimes | Sort-Object)
        $medianSeconds = [double]$orderedTimes[1]
        $measurements += [pscustomobject]@{ sessions=$sessions; date_from=$sample.date_from; date_to=$sample.date_to;
            elapsed_seconds=$medianSeconds; rank_rows=$expectedRows; trial_seconds=$trialTimes }
        Write-Evidence ("PROBE rank_stage sessions={0}|range={1}..{2}|rows={3}|median_seconds={4:F6}|trials={5}|read_only=true" -f $sessions,$sample.date_from,$sample.date_to,$expectedRows,$medianSeconds,($trialTimes -join ','))
    }
    $b1 = [math]::Log($measurements[1].elapsed_seconds/$measurements[0].elapsed_seconds)/[math]::Log(2)
    $b2 = [math]::Log($measurements[2].elapsed_seconds/$measurements[1].elapsed_seconds)/[math]::Log(2)
    $passed = ($b1 -le 1.3 -and $b2 -le 1.3)
    $state = if ($passed) { 'passed' } else { 'failed' }
    $probe = [pscustomobject]@{ database=$database; build_id=$BuildId; definition_sha256=$definition;
        transaction_scope='read_only_rank_stage'; state=$state; warmup_sessions=120;
        work_mem_mb=$WorkMemMegabytes; statement_timeout_minutes=$StatementTimeoutMinutes;
        io_concurrency=0; parallel_query_workers=0;
        measured_at=(Get-Date).ToUniversalTime().ToString('o'); measurements=$measurements;
        exponents=@($b1,$b2); passed=$passed }
    [IO.File]::WriteAllText($probePath,($probe | ConvertTo-Json -Depth 5),$utf8)
    Write-Evidence ("Read-only rank-stage scaling exponents={0:F6},{1:F6}; passed={2}; evidence={3}" -f $b1,$b2,$passed,$probePath)
    if (-not $passed) { throw 'Rank-stage scaling exceeds 1.3; investigate the measured plan before repair.' }
    return
}
if (-not (Test-Path -LiteralPath $probePath)) { throw 'Run this build in Probe mode before historical repair.' }
$probe = Get-Content -Raw -LiteralPath $probePath | ConvertFrom-Json
if ($probe.passed -ne $true -or $probe.database -cne $database -or $probe.build_id -cne $BuildId -or
    $probe.definition_sha256 -cne $definition -or $probe.measurements.Count -ne 3 -or
    $probe.transaction_scope -cne 'read_only_rank_stage' -or $probe.state -cne 'passed' -or
    $probe.warmup_sessions -ne 120 -or $probe.work_mem_mb -ne $WorkMemMegabytes -or
    $probe.statement_timeout_minutes -ne $StatementTimeoutMinutes -or
    $null -eq $probe.io_concurrency -or $probe.io_concurrency -ne 0 -or
    $null -eq $probe.parallel_query_workers -or $probe.parallel_query_workers -ne 0) {
    throw 'The required scaling evidence is missing, failed, or for different builder definitions.'
}
for ($i=0; $i -lt 3; $i++) {
    $sample = $probe.measurements[$i]
    if ($sample.sessions -ne @(30,60,120)[$i] -or $sample.elapsed_seconds -le 0 -or
        [double]::IsNaN($sample.elapsed_seconds) -or [double]::IsInfinity($sample.elapsed_seconds) -or
        $sample.rank_rows -le 0 -or $sample.trial_seconds.Count -ne 3) {
        throw 'Scaling evidence contains an invalid session count, duration or rank row count.'
    }
    if ($i -gt 0) {
        if ($sample.rank_rows -le $probe.measurements[$i-1].rank_rows) {
            throw 'Rank-stage sample rows did not increase with the effective-session window.'
        }
        $exponent = [math]::Log($sample.elapsed_seconds/$probe.measurements[$i-1].elapsed_seconds)/[math]::Log(2)
        if ($exponent -gt 1.3) { throw 'Scaling measurements exceed the required 1.3 exponent.' }
    }
}
$processed = 0
while ($cursor -le $last -and ($MaxChunks -eq 0 -or $processed -lt $MaxChunks)) {
    $nextMonth = [datetime]::new($cursor.Year,$cursor.Month,1).AddMonths(1)
    $end = $nextMonth.AddDays(-1)
    if ($end -gt $last) { $end = $last }
    $from = $cursor.ToString('yyyy-MM-dd',$culture)
    $to = $end.ToString('yyyy-MM-dd',$culture)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-Sql @"
BEGIN;
SET LOCAL statement_timeout='${StatementTimeoutMinutes}min';
SET LOCAL work_mem='${WorkMemMegabytes}MB';
SET LOCAL jit=off;
SELECT * FROM ops.repair_phase2_rank_chunk($build,'$from','$to');
COMMIT;
"@
        if ($result -notmatch '^\d+\|\d+\|\d+\|[0-9a-f]{64}\|[tf]$') {
            throw "Unexpected rank-repair result: $result"
        }
        $watch.Stop()
        Write-Evidence ("{0}..{1}|{2}|elapsed_ms={3}" -f $from,$to,$result,$watch.ElapsedMilliseconds)
    } catch {
        $watch.Stop()
        $failure = [string]$_
        Write-Evidence ("FAILED {0}..{1}|elapsed_ms={2}|{3}" -f $from,$to,$watch.ElapsedMilliseconds,$failure)
        try {
            $errorLiteral = Sql-Literal $failure
            $null = Invoke-Sql "SELECT ops.fail_phase2_rank_chunk($build,'$from','$to',$errorLiteral,$($watch.ElapsedMilliseconds))"
        } catch { Write-Evidence ("Failure audit could not be persisted: {0}" -f $_) }
        throw $failure
    }
    $processed++
    $cursor = $end.AddDays(1)
}
$status = Invoke-Sql "SELECT status,count(*),sum(v2_rows),sum(v3_rows) FROM ops.phase2_rank_repairs WHERE build_id=$build GROUP BY status ORDER BY status"
Write-Evidence ("Checkpoint after {0} ranges in this invocation: {1}" -f $processed,$status)
if ($cursor -le $last) { Write-Evidence ("Stopped at requested checkpoint; next date={0:yyyy-MM-dd}" -f $cursor) }
else { Write-Evidence 'All monthly ranges processed; run integrity and fresh-build parity before sign-off.' }
