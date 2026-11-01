param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'manifest.csv')
)

$ErrorActionPreference = 'Stop'
$psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    $psql = (Get-Command psql -ErrorAction Stop).Source
}

$previousOptions = $env:PGOPTIONS
try {
    $env:PGOPTIONS = (($previousOptions + ' -c default_transaction_read_only=on -c statement_timeout=30000 -c work_mem=16MB').Trim())
    $query = @'
COPY (
WITH target_symbols AS MATERIALIZED (
 SELECT DISTINCT l.symbol_id
 FROM feat.labels_daily l
 JOIN feat.phase2_label_targets_v3 t
   ON t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
  AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
  AND t.feature_set_hash=l.feature_set_hash
 WHERE l.label_status='READY'
   AND l.signal_date>=DATE '2018-11-01' AND l.signal_date<DATE '2019-01-01'
   AND l.entry_date<=DATE '2019-01-02' AND l.exit_date>=DATE '2019-01-02'
   AND t.feature_set_hash=feat.phase2_feature_set_hash_v3()
)
SELECT s.symbol_id,s.symbol,b.trade_date,
       b.c::numeric AS vndirect_close_thousand_vnd,
       b.v::numeric AS vndirect_volume_shares,
       b.landing_id AS vndirect_landing_id,
       b.source_row AS vndirect_source_row,
       rl.payload_sha256 AS vndirect_payload_sha256,
       rl.payload->'data'->b.source_row->>'close' AS archived_close,
       rl.payload->'data'->b.source_row->>'nmVolume' AS archived_nm_volume,
       rl.payload->'data'->b.source_row->>'ptVolume' AS archived_pt_volume
  FROM target_symbols ts
  JOIN core.symbols s USING(symbol_id)
  JOIN core.bars_daily_sources_ml_eligible b USING(symbol_id)
  JOIN raw.landings rl ON rl.landing_id=b.landing_id
 WHERE b.source='vndirect' AND b.adj_basis='unadjusted'
   AND b.trade_date=DATE '2019-01-02'
   AND rl.source='vndirect' AND rl.route='equity_ohlcv'
   AND rl.payload_sha256 ~ '^[0-9a-f]{64}$'
   AND NOT EXISTS (
       SELECT 1 FROM core.daily_price_limit_observations p
        WHERE p.symbol_id=b.symbol_id AND p.trade_date=b.trade_date
          AND p.source='vndirect'
   )
 ORDER BY s.symbol
) TO STDOUT WITH (FORMAT csv, HEADER true);
'@

    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    & $psql -X -q -v ON_ERROR_STOP=1 -U postgres -h 127.0.0.1 -p 5432 `
        -d vnsignal_phase2_report_20261019 -c $query > $resolvedOutput
    if ($LASTEXITCODE -ne 0) { throw "Manifest export failed with psql exit code $LASTEXITCODE." }

    $rows = Import-Csv -LiteralPath $resolvedOutput
    $uniqueSymbols = @($rows.symbol | Sort-Object -Unique).Count
    if ($rows.Count -ne 865 -or $uniqueSymbols -ne 865) {
        throw "Expected 865 distinct current-hash symbols; exported $($rows.Count) rows / $uniqueSymbols symbols."
    }
    if (@($rows | Where-Object {
        $_.trade_date -ne '2019-01-02' -or
        $_.vndirect_payload_sha256 -notmatch '^[0-9a-f]{64}$'
    }).Count -gt 0) {
        throw 'The target manifest contains a wrong date or unverified VNDIRECT landing hash.'
    }
    Write-Output "Exported $($rows.Count) missing-limit symbols from the disposable report clone."
} finally {
    $env:PGOPTIONS = $previousOptions
}
