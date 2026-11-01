[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DatabaseUrl,

    [ValidatePattern('^[A-Za-z0-9._-]{1,63}$')]
    [string]$ExpectedDatabaseName = 'vnsignal_phase2_report_20261019',

    [ValidatePattern('^[A-Za-z0-9._-]{1,100}$')]
    [string]$BuildId = ('phase2-full-' + (Get-Date -Format 'yyyyMMdd')),

    [ValidateSet('features', 'labels', 'fundamentals', 'features-labels', 'all')]
    [string]$Stage = 'all',

    [string]$DateFrom,
    [string]$DateTo,

    [ValidateRange(1, 3)]
    [int]$ChunkYears = 1,

    [ValidateRange(0, 36)]
    [int]$ChunkMonths = 0,

    [switch]$CalendarAlignedChunks,

    [ValidateRange(1, 250)]
    [int]$SymbolBatchSize = 60,

    [ValidateRange(1, 250)]
    [int]$V3ComputeBatchSize = 5,

    [ValidateRange(1, 30)]
    [int]$StatementTimeoutMinutes = 30,

    [string]$WorkMem = '128MB',
    [ValidatePattern('^[1-9][0-9]*(kB|MB|GB)$')]
    [string]$MaintenanceWorkMem = '16MB',
    [string]$TempFileLimit = '90GB',
    [string]$ReuseCacheScalingEvidencePath,
    [string]$PsqlPath = 'psql',

    [string]$VnpipePath = 'vnpipe',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function ConvertTo-SqlLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-Phase2Psql([string]$Sql, [switch]$Scalar, [switch]$StreamOutput, [string]$OutputLogPath) {
    $arguments = @('-X', '-v', 'ON_ERROR_STOP=1')
    if ($Scalar) { $arguments += @('-qAt') }
    $scriptPath = $null
    try {
        if ($Sql.Length -gt 12000 -or $Sql.Contains('\gexec') -or $Sql.Contains("`n")) {
            $scriptPath = Join-Path ([IO.Path]::GetTempPath()) ('vn-signal-phase2-' + [guid]::NewGuid().ToString('N') + '.sql')
            [IO.File]::WriteAllText($scriptPath, $Sql, [Text.UTF8Encoding]::new($false))
            $arguments += @('-f', $scriptPath, $DatabaseUrl)
        }
        else {
            $arguments += @('-c', $Sql, $DatabaseUrl)
        }
        # Windows PowerShell 5.1 converts native stderr into ErrorRecords. With
        # this script's Stop preference, a normal PostgreSQL NOTICE can abort
        # the pipeline and close psql before it finishes the transaction. Keep
        # stderr captured as output here; the psql exit code below remains the
        # authoritative failure signal.
        $previousErrorActionPreference = $ErrorActionPreference
        $streamWriter = $null
        try {
            $ErrorActionPreference = 'Continue'
            if ($StreamOutput) {
                $recentOutput = [System.Collections.Generic.Queue[string]]::new()
                if (-not [string]::IsNullOrWhiteSpace($OutputLogPath)) {
                    $streamWriter = [IO.StreamWriter]::new($OutputLogPath, $true, [Text.UTF8Encoding]::new($false))
                }
                & $PsqlPath @arguments 2>&1 | ForEach-Object {
                    $line = [string]$_
                    if ($streamWriter) { $streamWriter.WriteLine($line) }
                    if ($line -match '^\s*(\d{1,2})\s*\|\s*(15|30|60)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$') {
                        Write-Host ('CACHE sample {0}/90 symbols={1} rows={2} elapsed_ms={3}' -f $Matches[1].Trim(),$Matches[2].Trim(),$Matches[3].Trim(),$Matches[4].Trim())
                        if ($streamWriter) { $streamWriter.Flush() }
                    }
                    if ($recentOutput.Count -ge 80) { [void]$recentOutput.Dequeue() }
                    $recentOutput.Enqueue($line)
                    if ($line -match '(?i)(START (features|labels|fundamentals)|SKIP (features|labels|fundamentals)|phase 2 (sessions|market context rows|rank rows|price-day hash range)|cache scaling|ERROR:|FATAL:|WARNING:)') {
                        Write-Host $line
                    }
                }
                $output = $recentOutput.ToArray()
            }
            else {
                $output = & $PsqlPath @arguments 2>&1
            }
        }
        finally {
            try {
                if ($streamWriter) {
                    try { $streamWriter.Flush() }
                    finally { $streamWriter.Dispose() }
                }
            }
            finally {
                $ErrorActionPreference = $previousErrorActionPreference
            }
        }
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $details = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
            throw "psql failed with exit code $exitCode. $details"
        }
        return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    }
    finally {
        if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
            Remove-Item -LiteralPath $scriptPath -Force
        }
    }
}

if ($DatabaseUrl -match '://[^/]*:[^/@]+@') {
    throw 'Keep database passwords out of the connection URL; set PGPASSWORD or use the local credential store.'
}

if ([string]::IsNullOrWhiteSpace($DateFrom) -xor [string]::IsNullOrWhiteSpace($DateTo)) {
    throw 'Provide both -DateFrom and -DateTo, or omit both to use the v2 feature range.'
}
if ($CalendarAlignedChunks -and $ChunkMonths -ne 1) {
    throw '-CalendarAlignedChunks requires -ChunkMonths 1.'
}
if ([string]::IsNullOrWhiteSpace($DateFrom)) {
    $bounds = Invoke-Phase2Psql -Scalar -Sql @'
SELECT min(trade_date)::text||'|'||max(trade_date)::text
FROM feat.features_daily
WHERE feature_version='phase2-v2'
'@
    $parts = $bounds.Split('|')
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw 'No phase2-v2 feature-date range is available in the selected database.'
    }
    $DateFrom = $parts[0]
    $DateTo = $parts[1]
}
$rangeFromDate = [DateTime]::ParseExact($DateFrom, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$rangeToDate = [DateTime]::ParseExact($DateTo, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
if ($rangeFromDate -gt $rangeToDate) { throw '-DateFrom must be on or before -DateTo.' }

$stages = switch ($Stage) {
    'all' { @('features', 'labels', 'fundamentals') }
    'features-labels' { @('features', 'labels') }
    default { @($Stage) }
}
if ($stages -contains 'labels') {
    $oversizedLabelChunk = if ($ChunkMonths -gt 0) {
        -not $CalendarAlignedChunks -and $ChunkMonths -gt 12
    } else {
        $ChunkYears -gt 1
    }
    if ($oversizedLabelChunk) {
        throw 'Phase 2 label chunks are limited to 300 trading sessions; use -ChunkYears 1 or -ChunkMonths <=12.'
    }
}
$reuseCacheScalingEvidence = $null
if (-not [string]::IsNullOrWhiteSpace($ReuseCacheScalingEvidencePath)) {
    if ($stages -notcontains 'labels') {
        throw '-ReuseCacheScalingEvidencePath is valid only for a build that includes labels.'
    }
    $reuseCacheScalingEvidence = [IO.Path]::GetFullPath($ReuseCacheScalingEvidencePath)
    if (-not (Test-Path -LiteralPath $reuseCacheScalingEvidence -PathType Leaf)) {
        throw "Cache-scaling evidence file does not exist: $reuseCacheScalingEvidence"
    }
    $profileText = [IO.File]::ReadAllText($reuseCacheScalingEvidence)
    $expectedProfileHeaders = @(
        "(?m)^Build ID: $([regex]::Escape($BuildId))\r?$",
        '(?m)^Stage: labels\r?$',
        "(?m)^Symbol batch size: $SymbolBatchSize\r?$",
        "(?m)^V3 compute batch size: $V3ComputeBatchSize\r?$",
        "(?m)^Work memory: $([regex]::Escape($WorkMem))\r?$",
        "(?m)^Maintenance work memory: $([regex]::Escape($MaintenanceWorkMem))\r?$"
    )
    foreach ($headerPattern in $expectedProfileHeaders) {
        if ($profileText -notmatch $headerPattern) {
            throw 'Cache-scaling evidence must match this build ID, date range, and cache configuration.'
        }
    }
    $profileDateRange = [regex]::Match(
        $profileText,
        '(?m)^Date range: (?<from>[0-9]{4}-[0-9]{2}-[0-9]{2}) through (?<to>[0-9]{4}-[0-9]{2}-[0-9]{2})\r?$'
    )
    if (-not $profileDateRange.Success) {
        throw 'Cache-scaling evidence must include a valid build date range.'
    }
    $profileFromDate = [DateTime]::ParseExact($profileDateRange.Groups['from'].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $profileToDate = [DateTime]::ParseExact($profileDateRange.Groups['to'].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    if ($profileFromDate -gt $rangeFromDate -or $profileToDate -lt $rangeToDate) {
        throw 'Cache-scaling evidence date range must cover the requested build range.'
    }
    $profileMetric = [regex]::Match(
        $profileText,
        'NOTICE:\s+Phase 2 adjustment-cache row-scaling exponent (?<exponent>[0-9.]+), samples 15/30/60 symbols with [^\r\n]*projected cache time (?<projected>[0-9.]+) minutes \(budget (?<budget>[0-9.]+) minutes\)'
    )
    $assertPosition = $profileText.IndexOf('assert_phase2_adjustment_cache_scaling', [StringComparison]::Ordinal)
    $firstLabelStart = [regex]::Match($profileText, 'NOTICE:\s+START labels [0-9]{8}-[0-9]{8}')
    if (-not $profileMetric.Success -or $assertPosition -lt 0 -or -not $firstLabelStart.Success -or
        $assertPosition -gt $firstLabelStart.Index) {
        throw 'Cache-scaling evidence must show the scaling assertion and a subsequent label start.'
    }
    $priorProfileOutput = $profileText.Substring(0, $firstLabelStart.Index)
    if ($priorProfileOutput -match '(?m)^.*(?:ERROR:|FATAL:)') {
        throw 'Cache-scaling evidence contains an error before its first label start.'
    }
    $projectedMinutes = [double]::Parse($profileMetric.Groups['projected'].Value, [Globalization.CultureInfo]::InvariantCulture)
    $budgetMinutes = [double]::Parse($profileMetric.Groups['budget'].Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($projectedMinutes -gt $budgetMinutes) {
        throw 'Cache-scaling evidence projection exceeds its recorded budget.'
    }
}
$policySql = ''
if ($stages -contains 'labels') {
    $policyOutput = & $VnpipePath label-policy
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read validated label policy; build the current vnpipe executable.' }
    $policy = ($policyOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop
    foreach ($key in @('entry_ceiling_weight','multiple_locked_weight')) {
        if ($null -eq $policy.$key) { throw "Missing label policy field $key" }
        $value = [double]$policy.$key
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1) {
            throw "Invalid label policy field $key"
        }
    }
    $entryWeight = ([double]$policy.entry_ceiling_weight).ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $lockedWeight = ([double]$policy.multiple_locked_weight).ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $policySql = "SET LOCAL vnpipe.phase2_entry_ceiling_weight='$entryWeight';`nSET LOCAL vnpipe.phase2_multiple_locked_weight='$lockedWeight';"
    Write-Host "Label policy: entry ceiling=$entryWeight, multiple locked=$lockedWeight"
}
$labelSchemaGuard = if ($stages -contains 'labels') {
    @"
    AND current_database()='$ExpectedDatabaseName'
    AND to_regprocedure('ops.phase2_label_target_chunk_input_hash(date,date)') IS NOT NULL
    AND to_regprocedure('ops.phase2_label_targets_chunk_hash(date,date)') IS NOT NULL
    AND to_regprocedure('feat.build_phase2_label_targets_v3(date,date)') IS NOT NULL
    AND (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='ops' AND table_name='phase2_label_target_chunk_runs'
           AND column_name='label_build_id')=1
    AND position('vnpipe.phase2_label_build_id' IN
        pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure))>0
    AND position('SELECT v_hash,symbol_id,min(trade_date)' IN
        pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure))=0
    AND (length(pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure))
         -length(replace(pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure),
                         'SELECT v_hash,s.symbol_id,f.first_date','')))
        =2*length('SELECT v_hash,s.symbol_id,f.first_date')
    AND to_regprocedure('feat.refresh_phase2_execution_weights(date,date,date,bigint[])') IS NOT NULL
    AND position('DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102;' IN
        pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure))>0
    AND position('phase2_weight_unique_sessions_106' IN
        pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure))>0
    AND position('phase2_weight_vndirect_payload_rows_108' IN
        pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure))>0
    AND position('phase2_weight_payload_rows_selected_109' IN
        pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure))>0
"@
} else { '' }
$phase2SchemaReady = Invoke-Phase2Psql -Scalar -Sql @"
SELECT CASE WHEN (
    to_regprocedure('ops.phase2_execution_weight_policy()') IS NOT NULL
    AND
    to_regprocedure('ops.phase2_chunk_input_hash(text,date,date)') IS NOT NULL
    AND to_regprocedure('ops.phase2_chunk_output_hash(text,date,date)') IS NOT NULL
    $labelSchemaGuard
    AND to_regprocedure('ops.phase2_prepare_price_day_hashes(date,date)') IS NOT NULL
    AND (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='ops' AND table_name='feature_chunks'
           AND column_name IN ('input_sha256','output_sha256'))=2
    AND (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='ops' AND table_name='step_runs'
           AND column_name IN ('input_sha256','output_sha256'))=2
    AND to_regprocedure('feat.phase2_vndirect_adjustment_details_for_symbols(bigint[])') IS NOT NULL
    AND to_regprocedure('feat.prepare_phase2_adjustment_rows(boolean)') IS NOT NULL
    AND position('session-local point-in-time price input cache' in
        pg_get_functiondef('feat.prepare_phase2_adjustment_rows(boolean)'::regprocedure))>0
    AND to_regprocedure('feat.probe_phase2_adjustment_cache(integer)') IS NOT NULL
    AND to_regprocedure('feat.measure_phase2_cache_scaling()') IS NOT NULL
    AND to_regprocedure('feat.validate_phase2_cache_samples()') IS NOT NULL
    AND to_regprocedure('feat.phase2_cache_sample_batch_rows_ms(integer,bigint,double precision,integer,bigint,double precision)') IS NOT NULL
    AND to_regprocedure('feat.invalidate_phase2_price_cache_hashes()') IS NOT NULL
    AND to_regprocedure('feat.assert_phase2_adjustment_cache_scaling()') IS NOT NULL
    AND to_regprocedure('feat.begin_phase2_adjustment_rows(integer,integer)') IS NOT NULL
    AND to_regprocedure('feat.populate_phase2_adjustment_rows(integer)') IS NOT NULL
    AND to_regprocedure('feat.finish_phase2_adjustment_rows()') IS NOT NULL
    AND position('phase2_v3_compute_batch_size' IN
        pg_get_functiondef('feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure))>0
    AND to_regprocedure('feat.build_price_features_v3_year_impl(date,date,bigint[],date)') IS NOT NULL
    AND to_regprocedure('feat.build_price_features_v3_calendar_chunked(date,date,bigint[])') IS NOT NULL
) THEN 'ready' ELSE 'missing' END
"@
if ($phase2SchemaReady -ne 'ready') {
    throw 'Required Phase 2 migrations are missing or incomplete. Apply all repository migrations before running the builder.'
}
if ($stages -contains 'labels') {
    $downstreamTargetDate = Invoke-Phase2Psql -Scalar -Sql @"
SELECT coalesce(min(signal_date)::text,'none')
  FROM feat.phase2_label_targets_v3
 WHERE signal_date>DATE '$($rangeToDate.ToString('yyyy-MM-dd'))'
"@
    if ($downstreamTargetDate -ne 'none') {
        throw ("Label rebuild ending {0} would invalidate later derived targets starting {1}. Extend the range through the downstream targets or use a fresh report clone." -f $rangeToDate.ToString('yyyy-MM-dd'),$downstreamTargetDate)
    }
}
$functions = @{
    features     = 'feat.build_price_features_v3_internal'
    labels       = 'feat.build_labels_internal'
    fundamentals = 'feat.build_fundamental_features'
}
$buildLiteral = ConvertTo-SqlLiteral $BuildId
$runToken = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runInstance = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $runToken
$completed = 0
$pendingChunks = [System.Collections.Generic.List[object]]::new()

foreach ($stageName in $stages) {
    $stageLiteral = ConvertTo-SqlLiteral $stageName
    $cursor = [DateTime]::new($rangeFromDate.Year, $rangeFromDate.Month, $rangeFromDate.Day)
    while ($cursor -le $rangeToDate) {
        if ($ChunkMonths -gt 0) {
            if ($CalendarAlignedChunks) {
                $chunkEnd = [DateTime]::new($cursor.Year, $cursor.Month, 1).AddMonths(1).AddDays(-1)
            }
            else {
                $chunkEnd = $cursor.AddMonths($ChunkMonths).AddDays(-1)
            }
        }
        else {
            $yearEnd = [DateTime]::new($cursor.Year, 12, 31)
            $chunkEnd = if ($ChunkYears -eq 1) { $yearEnd } else { [DateTime]::new($cursor.Year + $ChunkYears - 1, 12, 31) }
        }
        if ($chunkEnd -gt $rangeToDate) { $chunkEnd = $rangeToDate }
        $chunkKey = '{0}-{1}' -f $cursor.ToString('yyyyMMdd'), $chunkEnd.ToString('yyyyMMdd')
        $chunkLiteral = ConvertTo-SqlLiteral $chunkKey
        $fromLiteral = "DATE '" + $cursor.ToString('yyyy-MM-dd') + "'"
        $toLiteral = "DATE '" + $chunkEnd.ToString('yyyy-MM-dd') + "'"

        $init = @"
INSERT INTO ops.feature_chunks(build_id,stage,chunk_key,date_from,date_to)
VALUES($buildLiteral,$stageLiteral,$chunkLiteral,$fromLiteral,$toLiteral)
ON CONFLICT(build_id,stage,chunk_key) DO UPDATE
SET date_from=EXCLUDED.date_from,date_to=EXCLUDED.date_to
WHERE ops.feature_chunks.status<>'done';
"@
        Invoke-Phase2Psql -Sql $init | Out-Null

        Write-Host "CHECK $stageName $chunkKey"
        $functionName = $functions[$stageName]
        $inputHashExpression = if ($stageName -eq 'labels') {
            "ops.phase2_label_target_chunk_input_hash($fromLiteral,$toLiteral)"
        } else { '' }
        if ([string]::IsNullOrWhiteSpace($inputHashExpression)) {
            $inputHashExpression = "ops.phase2_chunk_input_hash($stageLiteral,$fromLiteral,$toLiteral)"
        }
        $targetBuilder = if ($stageName -eq 'labels') {
            "PERFORM feat.build_phase2_label_targets_v3($fromLiteral,$toLiteral);"
        } else { '' }
        $targetOutputExpr = if ($stageName -eq 'labels') {
            "ops.phase2_hash_text(ops.phase2_chunk_output_hash($stageLiteral,$fromLiteral,$toLiteral)||'|'||ops.phase2_label_targets_chunk_hash($fromLiteral,$toLiteral))"
        } else {
            "ops.phase2_chunk_output_hash($stageLiteral,$fromLiteral,$toLiteral)"
        }
        $forceLiteral = if ($Force) { 'true' } else { 'false' }
        $policyExpression = if ($stageName -eq 'labels') { 'ops.phase2_execution_weight_policy()' } else { 'NULL::jsonb' }
        $labelBuildAssociation = if ($stageName -eq 'labels') { "SET LOCAL vnpipe.phase2_label_build_id=$buildLiteral;" } else { '' }
        $buildChunk = @"
BEGIN;
$policySql
$labelBuildAssociation
SET LOCAL statement_timeout='$($StatementTimeoutMinutes)min';
SET LOCAL temp_file_limit='$TempFileLimit';
SET LOCAL work_mem='$WorkMem';
SET LOCAL maintenance_work_mem='$MaintenanceWorkMem';
SET LOCAL jit=off;
SET LOCAL synchronous_commit=off;
SET LOCAL random_page_cost=1.1;
SET LOCAL vnpipe.phase2_symbol_batch_size='$SymbolBatchSize';
SET LOCAL vnpipe.phase2_v3_compute_batch_size='$V3ComputeBatchSize';
SET LOCAL application_name='phase2_$stageName';
DO `$phase2_chunk`$
DECLARE
    v_rows bigint;
    v_input_hash text;
    v_output_hash text;
    v_step_run_id bigint;
    v_error text;
    v_existing_status text;
    v_existing_hash text;
    v_current_output_hash text;
    v_execution_policy jsonb;
BEGIN
    BEGIN
        v_execution_policy := $policyExpression;
        v_input_hash := $inputHashExpression;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
        UPDATE ops.feature_chunks
           SET status='failed',rows=NULL,started_at=clock_timestamp(),finished_at=clock_timestamp(),
               input_sha256=NULL,execution_weight_policy=v_execution_policy,output_sha256=NULL,error=v_error
         WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral;
        INSERT INTO ops.step_runs(build_id,stage,chunk_key,status,started_at,finished_at,duration_ms,error,execution_weight_policy)
        VALUES($buildLiteral,$stageLiteral,$chunkLiteral,'failed',clock_timestamp(),clock_timestamp(),0,v_error,v_execution_policy);
        RETURN;
    END;

    SELECT status,input_sha256 INTO v_existing_status,v_existing_hash
      FROM ops.feature_chunks
     WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral;
    IF v_existing_status='done' AND v_existing_hash=v_input_hash AND NOT $forceLiteral THEN
        v_current_output_hash := $targetOutputExpr;
        IF (SELECT output_sha256 FROM ops.feature_chunks
             WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral)=v_current_output_hash THEN
            UPDATE ops.feature_chunks SET execution_weight_policy=v_execution_policy
             WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral;
            RAISE NOTICE 'SKIP % % input unchanged', $stageLiteral, $chunkLiteral;
            RETURN;
        END IF;
    END IF;

    RAISE NOTICE 'START % %', $stageLiteral, $chunkLiteral;
    UPDATE ops.feature_chunks
       SET status='running',rows=NULL,started_at=clock_timestamp(),finished_at=NULL,
           input_sha256=v_input_hash,execution_weight_policy=v_execution_policy,output_sha256=NULL,error=NULL
     WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral;
    INSERT INTO ops.step_runs(build_id,stage,chunk_key,status,input_sha256,execution_weight_policy)
    VALUES($buildLiteral,$stageLiteral,$chunkLiteral,'running',v_input_hash,v_execution_policy)
    RETURNING step_run_id INTO v_step_run_id;

    BEGIN
        v_rows := $functionName($fromLiteral,$toLiteral);
        $targetBuilder
        v_output_hash := $targetOutputExpr;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
        UPDATE ops.feature_chunks
           SET status='failed',rows=NULL,finished_at=clock_timestamp(),output_sha256=NULL,error=v_error
         WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral;
        UPDATE ops.step_runs
           SET status='failed',rows=NULL,finished_at=clock_timestamp(),
               duration_ms=(extract(epoch FROM (clock_timestamp()-started_at))*1000)::bigint,error=v_error
         WHERE step_run_id=v_step_run_id;
        RETURN;
    END;

    UPDATE ops.feature_chunks
       SET status='done',rows=v_rows,finished_at=clock_timestamp(),output_sha256=v_output_hash,error=NULL
     WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral;
    UPDATE ops.step_runs
       SET status='done',rows=v_rows,output_sha256=v_output_hash,finished_at=clock_timestamp(),
           duration_ms=(extract(epoch FROM (clock_timestamp()-started_at))*1000)::bigint
     WHERE step_run_id=v_step_run_id;
END
`$phase2_chunk`$;
COMMIT;
DO `$phase2_chunk_result`$
BEGIN
    IF EXISTS (SELECT 1 FROM ops.feature_chunks
                WHERE build_id=$buildLiteral AND stage=$stageLiteral AND chunk_key=$chunkLiteral
                  AND status='failed') THEN
        RAISE EXCEPTION 'Phase 2 chunk failed: % %', $stageLiteral, $chunkLiteral;
    END IF;
END
`$phase2_chunk_result`$;
"@
        [void]$pendingChunks.Add([pscustomobject]@{
            Stage = $stageName
            StageLiteral = $stageLiteral
            Key = $chunkKey
            Sql = $buildChunk
        })
        $cursor = $chunkEnd.AddDays(1)
    }
}

if ($pendingChunks.Count -gt 0) {
    $buildStageSql = ($pendingChunks | ForEach-Object { $_.Sql }) -join [Environment]::NewLine
    $cachePreludeSql = @"
-- One repeatable-read snapshot spans probes and every cache batch so concurrent
-- source updates cannot mix vintages. Each fill is a separate bounded SQL
-- statement, but the temporary cache is not durably resumable after session loss.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='$($StatementTimeoutMinutes)min';
SET LOCAL temp_file_limit='$TempFileLimit';
SET LOCAL work_mem='$WorkMem';
SET LOCAL maintenance_work_mem='$MaintenanceWorkMem';
SET LOCAL jit=off;
SET LOCAL synchronous_commit=off;
SET LOCAL random_page_cost=1.1;
SET LOCAL vnpipe.phase2_symbol_batch_size='$SymbolBatchSize';
SET LOCAL vnpipe.phase2_cache_time_budget_minutes='40';
SET LOCAL application_name='phase2_adjustment_cache';
-- Warm the input pages and the cache setup before collecting the fixed 90
-- observations. Stop prewarming only after two consecutive balanced blocks
-- are within the same 20 percent timing tolerance used by the measured guard.
-- Warmup observations stay separate; the full measured sample and every guard
-- remain required.
SELECT * FROM feat.probe_phase2_adjustment_cache(15);
SELECT * FROM feat.probe_phase2_adjustment_cache(30);
SELECT * FROM feat.probe_phase2_adjustment_cache(60);
CREATE TEMP TABLE phase2_cache_warmup_samples(
    block_no integer NOT NULL,sample_no integer NOT NULL,
    symbol_count integer NOT NULL,row_count bigint NOT NULL,duration_ms bigint NOT NULL,
    PRIMARY KEY(block_no,sample_no)
) ON COMMIT PRESERVE ROWS;
COMMENT ON TABLE pg_temp.phase2_cache_warmup_samples IS 'VN-Signal balanced cache steady-state warmup';
DO `$phase2_cache_warmup`$
DECLARE
    v_block integer;
    v_sample integer;
    v_symbols integer;
    v_probe record;
    v_stable boolean:=false;
    v_block_started_at timestamptz;
    v_block_elapsed_ms bigint;
    v_checkpoint_before jsonb;
    v_checkpoint_after jsonb;
    v_checkpoint_wait text;
    v_checkpoint_timed_delta bigint;
    v_checkpoint_requested_delta bigint;
    v_checkpoint_buffers_delta bigint;
    v_checkpoint_write_ms_delta numeric;
    v_checkpoint_sync_ms_delta numeric;
    v_prior_mean_15 double precision;
    v_prior_mean_30 double precision;
    v_prior_mean_60 double precision;
    v_mean_15 double precision;
    v_mean_30 double precision;
    v_mean_60 double precision;
    v_drift_15 numeric;
    v_drift_30 numeric;
    v_drift_60 numeric;
BEGIN
    FOR v_block IN 1..5 LOOP
        v_block_started_at:=clock_timestamp();
        v_checkpoint_before:=NULL;
        BEGIN
            PERFORM pg_stat_clear_snapshot();
            IF to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL THEN
                EXECUTE 'SELECT to_jsonb(s) FROM pg_catalog.pg_stat_checkpointer AS s'
                   INTO v_checkpoint_before;
            ELSIF to_regclass('pg_catalog.pg_stat_bgwriter') IS NOT NULL THEN
                EXECUTE 'SELECT to_jsonb(s) FROM pg_catalog.pg_stat_bgwriter AS s'
                   INTO v_checkpoint_before;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_checkpoint_before:=NULL;
        END;

        FOR v_sample IN 1..30 LOOP
            v_symbols:=CASE (v_sample-1)%9
                WHEN 0 THEN 15 WHEN 1 THEN 30 WHEN 2 THEN 60
                WHEN 3 THEN 30 WHEN 4 THEN 60 WHEN 5 THEN 15
                WHEN 6 THEN 60 WHEN 7 THEN 15 WHEN 8 THEN 30
            END;
            SELECT * INTO STRICT v_probe
              FROM feat.probe_phase2_adjustment_cache(v_symbols);
            INSERT INTO pg_temp.phase2_cache_warmup_samples(
                block_no,sample_no,symbol_count,row_count,duration_ms)
            VALUES(v_block,v_sample,v_probe.symbol_count,v_probe.row_count,v_probe.duration_ms);
        END LOOP;

        SELECT max(mean_ms) FILTER (WHERE symbol_count=15),
               max(mean_ms) FILTER (WHERE symbol_count=30),
               max(mean_ms) FILTER (WHERE symbol_count=60)
          INTO v_mean_15,v_mean_30,v_mean_60
          FROM (
              SELECT symbol_count,avg(duration_ms)::double precision AS mean_ms
              FROM pg_temp.phase2_cache_warmup_samples
              WHERE block_no=v_block GROUP BY symbol_count
          ) current_means;

        IF v_block>=2 THEN
            WITH block_means AS (
                SELECT block_no,symbol_count,min(row_count) AS row_count,
                       avg(duration_ms) AS mean_ms,count(*) AS samples
                FROM pg_temp.phase2_cache_warmup_samples
                WHERE block_no IN (v_block-1,v_block)
                GROUP BY block_no,symbol_count
            ), prior_block AS (
                SELECT * FROM block_means WHERE block_no=v_block-1
            ), current_block AS (
                SELECT * FROM block_means WHERE block_no=v_block
            )
            SELECT count(*)=3 AND bool_and(
                prior_block.samples=10 AND current_block.samples=10
                AND prior_block.row_count=current_block.row_count
                AND abs(current_block.mean_ms-prior_block.mean_ms)<=prior_block.mean_ms*0.20)
              INTO v_stable
            FROM prior_block JOIN current_block USING(symbol_count);

            SELECT max(mean_ms) FILTER (WHERE symbol_count=15),
                   max(mean_ms) FILTER (WHERE symbol_count=30),
                   max(mean_ms) FILTER (WHERE symbol_count=60)
              INTO v_prior_mean_15,v_prior_mean_30,v_prior_mean_60
              FROM (
                  SELECT symbol_count,avg(duration_ms)::double precision AS mean_ms
                  FROM pg_temp.phase2_cache_warmup_samples
                  WHERE block_no=v_block-1 GROUP BY symbol_count
              ) prior_means;
            v_drift_15:=round((abs(v_mean_15-v_prior_mean_15)/nullif(v_prior_mean_15,0)*100)::numeric,2);
            v_drift_30:=round((abs(v_mean_30-v_prior_mean_30)/nullif(v_prior_mean_30,0)*100)::numeric,2);
            v_drift_60:=round((abs(v_mean_60-v_prior_mean_60)/nullif(v_prior_mean_60,0)*100)::numeric,2);
        ELSE
            v_prior_mean_15:=NULL;
            v_prior_mean_30:=NULL;
            v_prior_mean_60:=NULL;
            v_drift_15:=NULL;
            v_drift_30:=NULL;
            v_drift_60:=NULL;
        END IF;

        v_checkpoint_after:=NULL;
        BEGIN
            PERFORM pg_stat_clear_snapshot();
            IF to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL THEN
                EXECUTE 'SELECT to_jsonb(s) FROM pg_catalog.pg_stat_checkpointer AS s'
                   INTO v_checkpoint_after;
            ELSIF to_regclass('pg_catalog.pg_stat_bgwriter') IS NOT NULL THEN
                EXECUTE 'SELECT to_jsonb(s) FROM pg_catalog.pg_stat_bgwriter AS s'
                   INTO v_checkpoint_after;
            END IF;
            SELECT concat_ws(':',wait_event_type,wait_event)
              INTO v_checkpoint_wait
              FROM pg_catalog.pg_stat_activity
             WHERE backend_type='checkpointer'
             LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_checkpoint_after:=NULL;
            v_checkpoint_wait:=NULL;
        END;
        v_checkpoint_timed_delta:=coalesce((v_checkpoint_after->>'num_timed')::bigint,
                                           (v_checkpoint_after->>'checkpoints_timed')::bigint,0)
            -coalesce((v_checkpoint_before->>'num_timed')::bigint,
                      (v_checkpoint_before->>'checkpoints_timed')::bigint,0);
        v_checkpoint_requested_delta:=coalesce((v_checkpoint_after->>'num_requested')::bigint,
                                               (v_checkpoint_after->>'checkpoints_req')::bigint,0)
            -coalesce((v_checkpoint_before->>'num_requested')::bigint,
                      (v_checkpoint_before->>'checkpoints_req')::bigint,0);
        v_checkpoint_buffers_delta:=coalesce((v_checkpoint_after->>'buffers_written')::bigint,
                                             (v_checkpoint_after->>'buffers_checkpoint')::bigint,0)
            -coalesce((v_checkpoint_before->>'buffers_written')::bigint,
                      (v_checkpoint_before->>'buffers_checkpoint')::bigint,0);
        v_checkpoint_write_ms_delta:=coalesce((v_checkpoint_after->>'write_time')::numeric,
                                              (v_checkpoint_after->>'checkpoint_write_time')::numeric,0)
            -coalesce((v_checkpoint_before->>'write_time')::numeric,
                      (v_checkpoint_before->>'checkpoint_write_time')::numeric,0);
        v_checkpoint_sync_ms_delta:=coalesce((v_checkpoint_after->>'sync_time')::numeric,
                                             (v_checkpoint_after->>'checkpoint_sync_time')::numeric,0)
            -coalesce((v_checkpoint_before->>'sync_time')::numeric,
                      (v_checkpoint_before->>'checkpoint_sync_time')::numeric,0);
        v_block_elapsed_ms:=(extract(epoch FROM (clock_timestamp()-v_block_started_at))*1000)::bigint;
        RAISE NOTICE 'Phase 2 cache scaling warmup block % of 5; stabilized=%; elapsed_ms=%; means_ms=[15:% 30:% 60:%]; drift_pct=[15:% 30:% 60:%]; checkpoint_delta=[timed:% requested:% buffers:% write_ms:% sync_ms:%]; checkpointer_wait=%',
            v_block,v_stable,v_block_elapsed_ms,
            round(v_mean_15::numeric,1),round(v_mean_30::numeric,1),round(v_mean_60::numeric,1),
            v_drift_15,v_drift_30,v_drift_60,
            v_checkpoint_timed_delta,v_checkpoint_requested_delta,v_checkpoint_buffers_delta,
            round(v_checkpoint_write_ms_delta,1),round(v_checkpoint_sync_ms_delta,1),
            coalesce(v_checkpoint_wait,'unavailable');
        IF v_stable THEN EXIT; END IF;
    END LOOP;
    IF NOT v_stable THEN
        RAISE EXCEPTION 'cache warmup did not stabilize after five balanced blocks';
    END IF;
END
`$phase2_cache_warmup`$;
-- Record the same fixed, balanced 90 observations as separate bounded SQL
-- statements. A single measure_phase2_cache_scaling() call can exceed the
-- statement timeout on a cold, memory-constrained machine even when every
-- individual probe is healthy. Keep the sample order, all timing rows, and
-- downstream stability/scaling assertions unchanged.
CREATE TEMP TABLE phase2_cache_samples(
    sample_no integer PRIMARY KEY,symbol_count integer NOT NULL,row_count bigint NOT NULL,
    duration_ms bigint NOT NULL,configured_batch_size integer NOT NULL,
    work_memory text NOT NULL,maintenance_memory text NOT NULL
) ON COMMIT PRESERVE ROWS;
COMMENT ON TABLE pg_temp.phase2_cache_samples IS 'VN-Signal fixed 90-sample cache benchmark';
SELECT format(`$phase2_cache_probe`$
WITH measured AS MATERIALIZED (
    SELECT * FROM feat.probe_phase2_adjustment_cache(%s)
), saved AS (
    INSERT INTO pg_temp.phase2_cache_samples(
        sample_no,symbol_count,row_count,duration_ms,configured_batch_size,
        work_memory,maintenance_memory)
    SELECT %s,m.symbol_count,m.row_count,m.duration_ms,
        coalesce(nullif(current_setting('vnpipe.phase2_symbol_batch_size',true),'')::integer,60),
        current_setting('work_mem'),current_setting('maintenance_work_mem')
    FROM measured m
    RETURNING sample_no
)
SELECT %s::integer AS sample_no,m.symbol_count,m.row_count,m.duration_ms
FROM measured m CROSS JOIN saved s;
`$phase2_cache_probe`$,
    CASE (sample_no-1)%9
        WHEN 0 THEN 15 WHEN 1 THEN 30 WHEN 2 THEN 60
        WHEN 3 THEN 30 WHEN 4 THEN 60 WHEN 5 THEN 15
        WHEN 6 THEN 60 WHEN 7 THEN 15 WHEN 8 THEN 30
    END,
    sample_no,
    sample_no
)
FROM generate_series(1,90) AS samples(sample_no)
ORDER BY sample_no
\gexec
SELECT feat.validate_phase2_cache_samples();
SELECT feat.assert_phase2_adjustment_cache_scaling();
SELECT feat.begin_phase2_adjustment_rows($SymbolBatchSize);
SELECT format('SELECT feat.populate_phase2_adjustment_rows(%s);',batch_no)
FROM (SELECT DISTINCT batch_no
      FROM pg_temp.phase2_adjustment_symbol_batches
      ORDER BY batch_no) batches
\gexec
SELECT feat.finish_phase2_adjustment_rows();
COMMIT;
"@
    if ($reuseCacheScalingEvidence) {
        # The benchmark and assertions are already proven for this exact build
        # and configuration. Rebuild the session-local input cache below, but
        # avoid rerunning the noisy performance profile after a session loss.
        $profilePreludePattern = 'SELECT \* FROM feat\.probe_phase2_adjustment_cache\(15\);(?s:.*?)SELECT feat\.begin_phase2_adjustment_rows'
        $cachePreludeWithoutProfile = [regex]::Replace(
            $cachePreludeSql,
            $profilePreludePattern,
            'SELECT feat.begin_phase2_adjustment_rows',
            1
        )
        if ($cachePreludeWithoutProfile -eq $cachePreludeSql) {
            throw 'Unable to isolate the cache-scaling profile from the session-local cache build.'
        }
        $cachePreludeSql = $cachePreludeWithoutProfile
        Write-Host "REUSE cache-scaling evidence $reuseCacheScalingEvidence; session-local adjustment rows will be rebuilt."
    }
    $buildStageSql = $cachePreludeSql + [Environment]::NewLine + $buildStageSql
    $pendingChunkPredicates = ($pendingChunks | ForEach-Object {
        $chunkLiteral = ConvertTo-SqlLiteral $_.Key
        "(stage=$($_.StageLiteral) AND chunk_key=$chunkLiteral)"
    }) -join ' OR '
    $evidenceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\evidence\phase2'))
    [IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
    $runLogPath = Join-Path $evidenceDirectory ('phase2_build_' + $BuildId + '_' + $runInstance + '.log')
    $logHeader = @(
        ('Build ID: ' + $BuildId)
        ('Stage: ' + ($stages -join ','))
        ('Date range: ' + $DateFrom + ' through ' + $DateTo)
        ('Statement timeout minutes: ' + $StatementTimeoutMinutes)
        ('Chunk months: ' + $ChunkMonths)
        ('Calendar-aligned monthly chunks: ' + $CalendarAlignedChunks)
        ('Chunk years: ' + $ChunkYears)
        ('Symbol batch size: ' + $SymbolBatchSize)
        ('V3 compute batch size: ' + $V3ComputeBatchSize)
        ('Work memory: ' + $WorkMem)
        ('Maintenance work memory: ' + $MaintenanceWorkMem)
        if ($reuseCacheScalingEvidence) { 'Reused cache-scaling evidence: ' + $reuseCacheScalingEvidence }
        ''
    )
    [IO.File]::WriteAllLines($runLogPath, [string[]]$logHeader, [Text.UTF8Encoding]::new($false))
    try {
        # One psql connection preserves the frozen input cache across feature,
        # and appends the full native transcript to disk as it runs. Keep only
        # the last 80 output lines in memory for compact failure diagnostics.
        # Cache probes and loads share a repeatable-read snapshot; each chunk
        # commits separately and the session-local cache persists across them.
        $null = Invoke-Phase2Psql -Sql $buildStageSql -StreamOutput -OutputLogPath $runLogPath
        Write-Host "EVIDENCE $runLogPath"
        $completed += $pendingChunks.Count
        foreach ($pendingChunk in $pendingChunks) {
            $chunkLiteral = ConvertTo-SqlLiteral $pendingChunk.Key
            $recordedRows = Invoke-Phase2Psql -Scalar -Sql "SELECT rows FROM ops.feature_chunks WHERE build_id=$buildLiteral AND stage=$($pendingChunk.StageLiteral) AND chunk_key=$chunkLiteral;"
            Write-Host "DONE  $($pendingChunk.Stage) $($pendingChunk.Key) rows=$recordedRows"
        }
    }
    catch {
        $fullMessage = [string]$_.Exception.Message
        $evidenceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\evidence\phase2'))
        [IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
        $failureLogPath = Join-Path $evidenceDirectory ('phase2_build_' + $BuildId + '.failed.' + $runInstance + '.log')
        $failureLog = @(
            ('Build ID: ' + $BuildId)
            ('Stage: ' + ($stages -join ','))
            ('Date range: ' + $DateFrom + ' through ' + $DateTo)
            ('Failure recorded at: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
            ('Native transcript: ' + $runLogPath)
            ''
            $fullMessage
        )
        [IO.File]::WriteAllLines(
            $failureLogPath,
            [string[]]$failureLog,
            [Text.UTF8Encoding]::new($false)
        )
        Write-Host "FAILURE EVIDENCE $failureLogPath"
        $message = $fullMessage
        if ($message.Length -gt 4000) { $message = $message.Substring($message.Length - 4000) }
        $errorLiteral = ConvertTo-SqlLiteral $message
        $failedChunkInfo = $null
        if (Test-Path -LiteralPath $runLogPath) {
            $lastStartedChunk = $null
            $lastStartedChunkCommitted = $false
            foreach ($line in [IO.File]::ReadLines($runLogPath)) {
                if ($line -match 'NOTICE:\s+START\s+(features|labels|fundamentals)\s+([0-9]{8}-[0-9]{8})') {
                    $lastStartedChunk = '{0}|{1}' -f $Matches[1],$Matches[2]
                    $lastStartedChunkCommitted = $false
                }
                elseif ($lastStartedChunk -and $line -match '^\s*COMMIT\s*$') {
                    $lastStartedChunkCommitted = $true
                }
            }
            if ($lastStartedChunk -and -not $lastStartedChunkCommitted) {
                $activeParts = $lastStartedChunk -split '\|', 2
                if (@($pendingChunks | Where-Object {
                    $_.Stage -eq $activeParts[0] -and $_.Key -eq $activeParts[1]
                }).Count -eq 1) {
                    $failedChunkInfo = $lastStartedChunk
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($failedChunkInfo)) {
            $failedChunkInfo = Invoke-Phase2Psql -Scalar -Sql @"
SELECT stage||'|'||chunk_key FROM ops.feature_chunks
WHERE build_id=$buildLiteral AND ($pendingChunkPredicates) AND status<>'done'
ORDER BY CASE stage WHEN 'features' THEN 1 WHEN 'labels' THEN 2 ELSE 3 END,date_from
LIMIT 1;
"@
        }
        if ([string]::IsNullOrWhiteSpace($failedChunkInfo)) {
            throw "Phase 2 failed before a pending chunk could be identified. Full evidence: $failureLogPath. $message"
        }
        $failedParts = $failedChunkInfo -split '\|', 2
        $failedStageLiteral = ConvertTo-SqlLiteral $failedParts[0]
        $failedChunkLiteral = ConvertTo-SqlLiteral $failedParts[1]
        $fail = @"
DO `$phase2_record_failure`$
DECLARE
    v_status text;
BEGIN
    SELECT status INTO v_status FROM ops.feature_chunks
     WHERE build_id=$buildLiteral AND stage=$failedStageLiteral AND chunk_key=$failedChunkLiteral;
    IF v_status IS DISTINCT FROM 'failed' THEN
        UPDATE ops.feature_chunks
           SET status='failed',rows=NULL,started_at=coalesce(started_at,clock_timestamp()),
               finished_at=clock_timestamp(),output_sha256=NULL,error=$errorLiteral
         WHERE build_id=$buildLiteral AND stage=$failedStageLiteral AND chunk_key=$failedChunkLiteral;
        INSERT INTO ops.step_runs(build_id,stage,chunk_key,status,started_at,finished_at,duration_ms,error)
        VALUES($buildLiteral,$failedStageLiteral,$failedChunkLiteral,'failed',clock_timestamp(),clock_timestamp(),0,$errorLiteral);
    END IF;
END
`$phase2_record_failure`$;
"@
        Invoke-Phase2Psql -Sql $fail | Out-Null
        # The durable file retains the full native transcript. Re-throwing that
        # transcript makes PowerShell format hundreds of kilobytes as an error
        # record on a memory-constrained desktop, delaying terminal status.
        throw "Phase 2 chunk failed: $failedChunkInfo. Full evidence: $failureLogPath. $message"
    }
}

$summary = Invoke-Phase2Psql -Sql @"
SELECT stage,status,count(*) AS chunks,coalesce(sum(rows),0) AS rows
FROM ops.feature_chunks
WHERE build_id=$buildLiteral
GROUP BY stage,status
ORDER BY stage,status;
"@
Write-Host "Chunks checked this run: $completed"
Write-Output $summary
