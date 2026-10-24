$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
$reportSql = Join-Path $repoRoot 'sql\diagnostics\phase2_integrity_report_chunked.sql'
$targetDsn = 'postgresql://postgres@localhost:5432/vnsignal_phase2_report_20261019'
$buildId = 'phase2-rank-repair-055-20261022'
$lastEnd = [datetime]::ParseExact('2026-10-17', 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$cursor = [datetime]::ParseExact('2018-10-01', 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)

$credential = Import-Clixml "$env:LOCALAPPDATA\VN-Signal\db-credential.xml"
$env:PGPASSWORD = [System.Net.NetworkCredential]::new('', $credential.Password).Password
$env:PGCONNECT_TIMEOUT = '15'

try {
    $firstChunk = $true
    while ($cursor -lt $lastEnd) {
        $chunkEnd = $cursor.AddMonths(1)
        if ($chunkEnd -gt $lastEnd) { $chunkEnd = $lastEnd }
        $chunkStartText = $cursor.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $chunkEndText = $chunkEnd.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $reportOps = if ($firstChunk) { 'true' } else { 'false' }

        Write-Output "CHUNK $chunkStartText/$chunkEndText"
        & $psql -X -w -d $targetDsn -v ON_ERROR_STOP=1 `
            -v "chunk_start=$chunkStartText" -v "chunk_end=$chunkEndText" `
            -v "build_id=$buildId" -v "report_ops=$reportOps" -f $reportSql
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        $cursor = $chunkEnd
        $firstChunk = $false
    }
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue
}
