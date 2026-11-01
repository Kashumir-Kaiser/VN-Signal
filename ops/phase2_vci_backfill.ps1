[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DatabaseUrl,

    [ValidatePattern('^[A-Za-z0-9._-]{1,100}$')]
    [string]$BuildId = ('phase2-vci-backfill-044-' + (Get-Date -Format 'yyyyMMdd')),

    [ValidateRange(1, 30)]
    [int]$ChunkDays = 30,

    [ValidateRange(0, 10000)]
    [int]$MaxChunks = 0,

    [ValidateRange(1, 30)]
    [int]$StatementTimeoutMinutes = 25,

    [string]$WorkMem = '128MB',
    [string]$PsqlPath = 'psql'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-SqlLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-Psql([string]$Sql, [switch]$Scalar, [switch]$Quiet) {
    $arguments = @('-X', '-v', 'ON_ERROR_STOP=1')
    if ($Scalar) { $arguments += @('-qAt', '-F', '|') }
    $arguments += @('-c', $Sql, $DatabaseUrl)
    $output = & $PsqlPath @arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw "psql failed with exit code $exitCode. $details"
    }
    $result = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if (-not $Quiet -and $result) { Write-Host $result }
    return $result
}

if ($DatabaseUrl -match '://[^/]*:[^/@]+@') {
    throw 'Keep database passwords out of the connection URL; set PGPASSWORD or use the local credential store.'
}
if ($WorkMem -notmatch '^\d+(kB|MB|GB)$') {
    throw '-WorkMem must be an integer followed by kB, MB, or GB.'
}

$databaseName = Invoke-Psql -Scalar -Sql 'SELECT current_database();'
if ($databaseName -notmatch '(_report_|_disposable$|_test$|_ci(?:_|$))' -or
    $databaseName -in @('vnsignal', 'postgres', 'template0', 'template1')) {
    throw "Refusing VCI backfill on '$databaseName'. Use the disposable Phase 2 report clone or a test database."
}

$buildLiteral = ConvertTo-SqlLiteral $BuildId
$schemaReady = Invoke-Psql -Scalar -Sql @'
SELECT CASE WHEN
    to_regprocedure('ops.prepare_phase2_vci_backfill(text,integer)') IS NOT NULL
    AND to_regprocedure('ops.backfill_phase2_vci_chunk(text,date,date)') IS NOT NULL
    AND to_regprocedure('ops.fail_phase2_vci_chunk(text,date,date,text)') IS NOT NULL
    AND to_regprocedure('ops.phase2_chunk_output_hash(text,date,date)') IS NOT NULL
THEN 'ready' ELSE 'missing' END;
'@
if ($schemaReady -ne 'ready') {
    throw 'Apply the Phase 2 VCI migration before running this backfill.'
}

$evidenceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\evidence\phase2'))
[IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
$logPath = Join-Path $evidenceDirectory ('phase2_vci_backfill_' + $BuildId + '.log')
$log = [System.Collections.Generic.List[string]]::new()
$log.Add('Build ID: ' + $BuildId)
$log.Add('Database: ' + $databaseName)
$log.Add('Chunk days: ' + $ChunkDays)
$log.Add('Statement timeout minutes: ' + $StatementTimeoutMinutes)
$log.Add('')

$prepareSql = @"
BEGIN;
SET LOCAL statement_timeout='$($StatementTimeoutMinutes)min';
SET LOCAL work_mem='$WorkMem';
SET LOCAL jit=off;
SELECT * FROM ops.prepare_phase2_vci_backfill($buildLiteral,$ChunkDays);
COMMIT;
"@
$prepared = Invoke-Psql -Scalar -Quiet -Sql $prepareSql
$preparedParts = $prepared -split '\|', 5
if ($preparedParts.Count -ne 5 -or $preparedParts[1] -notmatch '^[0-9a-f]{64}$' -or
    $preparedParts[2] -notmatch '^\d{4}-\d{2}-\d{2}$' -or
    $preparedParts[3] -notmatch '^\d{4}-\d{2}-\d{2}$' -or
    $preparedParts[4] -notmatch '^\d+$') {
    throw 'VCI context preparation returned invalid bounds, row count, chunk count, or hash.'
}
$log.Add('Date range: ' + $preparedParts[2] + ' through ' + $preparedParts[3])
$log.Add('Expected chunks: ' + $preparedParts[4])
$log.Add(('Context rows: ' + $preparedParts[0]))
$log.Add(('Context SHA-256: ' + $preparedParts[1]))

[IO.File]::WriteAllLines($logPath, $log.ToArray(), [Text.UTF8Encoding]::new($false))
$pendingSql = @"
SELECT date_from::text||'|'||date_to::text
FROM ops.phase2_vci_backfill_chunks
WHERE build_id=$buildLiteral AND status<>'done'
ORDER BY date_from;
"@
if ($MaxChunks -gt 0) { $pendingSql = ($pendingSql -replace ';\s*$', '') + " LIMIT $MaxChunks;" }
$pendingText = Invoke-Psql -Scalar -Quiet -Sql $pendingSql
$pendingRanges = @()
if (-not [string]::IsNullOrWhiteSpace($pendingText)) {
    $pendingRanges = @($pendingText -split [Environment]::NewLine | Where-Object { $_ })
}
foreach ($pendingRange in $pendingRanges) {
    $rangeParts = $pendingRange -split '\|', 2
    if ($rangeParts.Count -ne 2) { throw "Invalid planned date chunk: $pendingRange" }
    $fromText = $rangeParts[0]
    $toText = $rangeParts[1]
    if ($fromText -notmatch '^\d{4}-\d{2}-\d{2}$' -or
        $toText -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Invalid planned date chunk: $pendingRange"
    }
    $fromLiteral = "DATE '$fromText'"
    $toLiteral = "DATE '$toText'"
    $chunkSql = @"
BEGIN;
SET LOCAL statement_timeout='$($StatementTimeoutMinutes)min';
SET LOCAL work_mem='$WorkMem';
SET LOCAL jit=off;
SET LOCAL application_name='phase2_vci_backfill';
SELECT * FROM ops.backfill_phase2_vci_chunk($buildLiteral,$fromLiteral,$toLiteral);
COMMIT;
"@
    try {
        $chunkResult = Invoke-Psql -Scalar -Quiet -Sql $chunkSql
        $chunkParts = $chunkResult -split '\|', 3
        if ($chunkParts.Count -ne 3 -or $chunkParts[2] -notmatch '^[0-9a-f]{64}$') {
            throw 'Chunk returned an invalid row count or output hash.'
        }
        $line = "DONE $fromText through $toText rows=$($chunkParts[0]) changed=$($chunkParts[1]) sha256=$($chunkParts[2])"
        $log.Add($line)
        Write-Host $line
        [IO.File]::WriteAllLines($logPath, $log.ToArray(), [Text.UTF8Encoding]::new($false))
    }
    catch {
        $failure = [string]$_.Exception.Message
        $errorLiteral = ConvertTo-SqlLiteral $failure
        try {
            Invoke-Psql -Quiet -Sql "SELECT ops.fail_phase2_vci_chunk($buildLiteral,$fromLiteral,$toLiteral,$errorLiteral);" | Out-Null
        }
        catch {
            $failure += ' Failure status could not be recorded: ' + [string]$_.Exception.Message
        }
        $log.Add("FAILED $fromText through $toText")
        $log.Add($failure)
        [IO.File]::WriteAllLines($logPath, $log.ToArray(), [Text.UTF8Encoding]::new($false))
        throw "VCI backfill stopped at $fromText through $toText. Evidence: $logPath. $failure"
    }
}

$summary = Invoke-Psql -Sql @"
SELECT build_id,status,context_rows,context_sha256
FROM ops.phase2_vci_backfill_runs
WHERE build_id=$buildLiteral;
SELECT status,count(*) AS chunks,coalesce(sum(rows),0) AS rows,
       coalesce(sum(changed_rows),0) AS changed_rows
FROM ops.phase2_vci_backfill_chunks
WHERE build_id=$buildLiteral
GROUP BY status ORDER BY status;
"@ -Quiet
$finalStatus = Invoke-Psql -Scalar -Sql @"
SELECT CASE WHEN r.status='complete'
                  AND (SELECT count(*) FROM ops.phase2_vci_backfill_chunks c
                       WHERE c.build_id=r.build_id AND c.status='done')=r.expected_chunks
            THEN 'complete' ELSE 'incomplete' END
FROM ops.phase2_vci_backfill_runs r
WHERE r.build_id=$buildLiteral;
"@
if ($finalStatus -ne 'complete') {
    $log.Add('')
    $log.Add(('Checkpoint status: incomplete; remaining chunks are resumable. MaxChunks=' + $MaxChunks))
    $log.Add($summary)
    [IO.File]::WriteAllLines($logPath, $log.ToArray(), [Text.UTF8Encoding]::new($false))
    if ($MaxChunks -eq 0) {
        throw "VCI backfill did not complete all planned chunks. Evidence: $logPath"
    }
    Write-Host "CHECKPOINT $logPath"
    Write-Host $summary
    return
}
$log.Add('')
$log.Add('Final status:')
$log.Add($summary)
[IO.File]::WriteAllLines($logPath, $log.ToArray(), [Text.UTF8Encoding]::new($false))
Write-Host "EVIDENCE $logPath"
Write-Host $summary
