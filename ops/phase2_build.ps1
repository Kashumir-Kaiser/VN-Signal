[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DatabaseUrl,

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

    [ValidateRange(1, 250)]
    [int]$SymbolBatchSize = 60,

    [ValidateRange(1, 30)]
    [int]$StatementTimeoutMinutes = 30,

    [string]$WorkMem = '128MB',
    [ValidatePattern('^[1-9][0-9]*(kB|MB|GB)$')]
    [string]$MaintenanceWorkMem = '16MB',
    [string]$TempFileLimit = '90GB',
    [string]$PsqlPath = 'psql',

    [string]$VnpipePath = 'vnpipe',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function ConvertTo-SqlLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-Phase2Psql([string]$Sql, [switch]$Scalar, [switch]$StreamOutput) {
    $arguments = @('-X', '-v', 'ON_ERROR_STOP=1')
    if ($Scalar) { $arguments += @('-qAt') }
    $scriptPath = $null
    try {
        if ($Sql.Length -gt 12000 -or $Sql.Contains('\gexec')) {
            $scriptPath = Join-Path ([IO.Path]::GetTempPath()) ('vn-signal-phase2-' + [guid]::NewGuid().ToString('N') + '.sql')
            [IO.File]::WriteAllText($scriptPath, $Sql, [Text.UTF8Encoding]::new($false))
            $arguments += @('-f', $scriptPath, $DatabaseUrl)
        }
        else {
            $arguments += @('-c', $Sql, $DatabaseUrl)
        }
        if ($StreamOutput) {
            $captured = [System.Collections.Generic.List[string]]::new()
            & $PsqlPath @arguments 2>&1 | ForEach-Object {
                $line = [string]$_
                [void]$captured.Add($line)
                Write-Host $line
            }
            $output = $captured.ToArray()
        }
        else {
            $output = & $PsqlPath @arguments 2>&1
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
    AND to_regprocedure('ops.phase2_label_target_chunk_input_hash(date,date)') IS NOT NULL
    AND to_regprocedure('ops.phase2_label_targets_chunk_hash(date,date)') IS NOT NULL
    AND to_regprocedure('feat.build_phase2_label_targets_v3(date,date)') IS NOT NULL
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
    AND to_regprocedure('feat.invalidate_phase2_price_cache_hashes()') IS NOT NULL
    AND to_regprocedure('feat.assert_phase2_adjustment_cache_scaling()') IS NOT NULL
    AND to_regprocedure('feat.begin_phase2_adjustment_rows(integer,integer)') IS NOT NULL
    AND to_regprocedure('feat.populate_phase2_adjustment_rows(integer)') IS NOT NULL
    AND to_regprocedure('feat.finish_phase2_adjustment_rows()') IS NOT NULL
) THEN 'ready' ELSE 'missing' END
"@
if ($phase2SchemaReady -ne 'ready') {
    throw 'Required Phase 2 migrations are missing or incomplete. Apply all repository migrations before running the builder.'
}
$functions = @{
    features     = 'feat.build_price_features_v3_internal'
    labels       = 'feat.build_labels_internal'
    fundamentals = 'feat.build_fundamental_features'
}
$buildLiteral = ConvertTo-SqlLiteral $BuildId
$completed = 0
$pendingChunks = [System.Collections.Generic.List[object]]::new()

foreach ($stageName in $stages) {
    $stageLiteral = ConvertTo-SqlLiteral $stageName
    $cursor = [DateTime]::new($rangeFromDate.Year, $rangeFromDate.Month, $rangeFromDate.Day)
    while ($cursor -le $rangeToDate) {
        if ($ChunkMonths -gt 0) {
            $chunkEnd = $cursor.AddMonths($ChunkMonths).AddDays(-1)
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
        $buildChunk = @"
BEGIN;
$policySql
SET LOCAL statement_timeout='$($StatementTimeoutMinutes)min';
SET LOCAL temp_file_limit='$TempFileLimit';
SET LOCAL work_mem='$WorkMem';
SET LOCAL maintenance_work_mem='$MaintenanceWorkMem';
SET LOCAL jit=off;
SET LOCAL synchronous_commit=off;
SET LOCAL random_page_cost=1.1;
SET LOCAL vnpipe.phase2_symbol_batch_size='$SymbolBatchSize';
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
-- Fixed balanced repetitions retain every timing and reject unstable block means.
SELECT * FROM feat.measure_phase2_cache_scaling();
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
    $buildStageSql = $cachePreludeSql + [Environment]::NewLine + $buildStageSql
    $pendingChunkPredicates = ($pendingChunks | ForEach-Object {
        $chunkLiteral = ConvertTo-SqlLiteral $_.Key
        "(stage=$($_.StageLiteral) AND chunk_key=$chunkLiteral)"
    }) -join ' OR '
    try {
        # One psql connection preserves the frozen input cache across feature,
        # label, and fundamentals chunks. Cache probes and loads share one
        # repeatable-read snapshot; each batch is its own timed SQL statement.
        $runOutput = Invoke-Phase2Psql -Sql $buildStageSql -StreamOutput
        $evidenceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\evidence\phase2'))
        [IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
        $runLogPath = Join-Path $evidenceDirectory ('phase2_build_' + $BuildId + '.log')
        $logHeader = @(
            ('Build ID: ' + $BuildId)
            ('Stage: ' + ($stages -join ','))
            ('Date range: ' + $DateFrom + ' through ' + $DateTo)
            ('Statement timeout minutes: ' + $StatementTimeoutMinutes)
            ('Chunk months: ' + $ChunkMonths)
            ('Chunk years: ' + $ChunkYears)
            ('Symbol batch size: ' + $SymbolBatchSize)
            ('Maintenance work memory: ' + $MaintenanceWorkMem)
            ''
        )
        [IO.File]::WriteAllLines(
            $runLogPath,
            [string[]]($logHeader + ($runOutput -split [Environment]::NewLine)),
            [Text.UTF8Encoding]::new($false)
        )
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
        $failureTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $failureLogPath = Join-Path $evidenceDirectory ('phase2_build_' + $BuildId + '.failed.' + $failureTimestamp + '.log')
        $failureLog = @(
            ('Build ID: ' + $BuildId)
            ('Stage: ' + ($stages -join ','))
            ('Date range: ' + $DateFrom + ' through ' + $DateTo)
            ('Failure recorded at: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
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
        $failedChunkInfo = Invoke-Phase2Psql -Scalar -Sql @"
SELECT stage||'|'||chunk_key FROM ops.feature_chunks
WHERE build_id=$buildLiteral AND ($pendingChunkPredicates) AND status<>'done'
ORDER BY CASE stage WHEN 'features' THEN 1 WHEN 'labels' THEN 2 ELSE 3 END,date_from
LIMIT 1;
"@
        if ([string]::IsNullOrWhiteSpace($failedChunkInfo)) { throw }
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
        throw
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
