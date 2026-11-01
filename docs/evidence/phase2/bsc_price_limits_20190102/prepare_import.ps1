param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'manifest.csv'),
    [string]$CapturePath = (Join-Path $PSScriptRoot 'capture.jsonl'),
    [string]$QuarantinePath = (Join-Path $PSScriptRoot 'quarantine.jsonl'),
    [string]$StagePath = (Join-Path $PSScriptRoot 'landing_stage.tsv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Convert-CellNumber([string]$Text) {
    $number = ($Text -replace '[,\s]', '')
    return [decimal]::Parse($number,[System.Globalization.CultureInfo]::InvariantCulture)
}

function Read-JsonLines([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(
        [System.IO.File]::ReadLines([System.IO.Path]::GetFullPath($Path)) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $jsonLine = $_
                $item = $jsonLine | ConvertFrom-Json
                # ConvertFrom-Json converts ISO timestamps to local DateTime
                # objects in Windows PowerShell. Preserve the original UTC
                # offset string so CSV COPY is locale-independent and exact.
                $timestampMatch = [regex]::Match(
                    $jsonLine,
                    '"fetched_at"\s*:\s*"(?<value>[^"\\]+)"'
                )
                if ($timestampMatch.Success) {
                    $item.fetched_at = $timestampMatch.Groups['value'].Value
                }
                $item
            }
    )
}

$manifest = @(Import-Csv -LiteralPath $ManifestPath)
if ($manifest.Count -ne 865 -or @($manifest.symbol | Sort-Object -Unique).Count -ne 865) {
    throw "Expected 865 unique target symbols; found $($manifest.Count) rows."
}
$manifestBySymbol = @{}
foreach ($row in $manifest) { $manifestBySymbol[[string]$row.symbol] = $row }

$capture = @(Read-JsonLines $CapturePath)
$quarantine = @(Read-JsonLines $QuarantinePath)
$captureBySymbol = @{}
foreach ($record in $capture) {
    $symbol = [string]$record.symbol
    if (-not $manifestBySymbol.ContainsKey($symbol)) { throw "Capture contains an unlisted symbol: $symbol." }
    if ($captureBySymbol.ContainsKey($symbol)) { throw "Capture contains a duplicate symbol: $symbol." }
    if ($record.status -ne 'MATCHED' -or $record.trade_date -ne '2019-01-02') {
        throw "Capture contains a non-matched record for $symbol."
    }
    if ([string]$record.fetched_at -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$') {
        throw "Capture timestamp is not preserved as an ISO-8601 offset value for $symbol."
    }
    $target = $manifestBySymbol[$symbol]
    $rawBytes = [Convert]::FromBase64String([string]$record.raw_response_base64)
    if ((Get-Sha256Hex $rawBytes) -cne [string]$record.raw_response_sha256) {
        throw "BSC raw-response SHA-256 does not verify for $symbol."
    }
    $rawText = [System.Text.Encoding]::UTF8.GetString($rawBytes).TrimStart([char]0xFEFF)
    if (($record.request.PSObject.Properties.Name -contains 'security') -or
        ($record.source_response.PSObject.Properties.Name -contains 'security')) {
        throw "BSC capture unexpectedly includes a request token field for $symbol."
    }
    $responseFromBytes = $rawText | ConvertFrom-Json
    if (-not $responseFromBytes.success -or
        [string]$responseFromBytes.data.html -cne [string]$record.source_response.data.html -or
        [string]$record.normalized_row.source_row_html -notin @([regex]::Matches(
            [string]$responseFromBytes.data.html,
            '<tr\b[^>]*>.*?</tr>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        ) | ForEach-Object { $_.Value })) {
        throw "BSC normalized row is not present in its exact response body for $symbol."
    }
    if (@($record.normalized_row.source_cells).Count -ne 10) {
        throw "BSC source row does not retain ten cells for $symbol."
    }
    $localClose = [decimal]::Parse([string]$target.vndirect_close_thousand_vnd,[System.Globalization.CultureInfo]::InvariantCulture) * 1000
    $localVolume = [decimal]::Parse([string]$target.vndirect_volume_shares,[System.Globalization.CultureInfo]::InvariantCulture)
    $archivedClose = [decimal]::Parse([string]$target.archived_close,[System.Globalization.CultureInfo]::InvariantCulture) * 1000
    $archivedVolume = [decimal]::Parse([string]$target.archived_nm_volume,[System.Globalization.CultureInfo]::InvariantCulture)
    $closeVnd = [decimal]::Parse([string]$record.normalized_row.close_price_vnd,[System.Globalization.CultureInfo]::InvariantCulture)
    $volume = [decimal]::Parse([string]$record.normalized_row.matched_volume_shares,[System.Globalization.CultureInfo]::InvariantCulture)
    $reference = [decimal]::Parse([string]$record.normalized_row.reference_price_vnd,[System.Globalization.CultureInfo]::InvariantCulture)
    $ceiling = [decimal]::Parse([string]$record.normalized_row.ceiling_price_vnd,[System.Globalization.CultureInfo]::InvariantCulture)
    $floor = [decimal]::Parse([string]$record.normalized_row.floor_price_vnd,[System.Globalization.CultureInfo]::InvariantCulture)
    if ($record.normalized_row.code -cne $symbol -or
        $closeVnd -ne $localClose -or $closeVnd -ne $archivedClose -or
        $volume -ne $localVolume -or $volume -ne $archivedVolume -or
        $reference -le 0 -or $ceiling -le 0 -or $floor -le 0 -or $ceiling -lt $floor) {
        throw "Captured BSC row no longer passes its exact VNDIRECT close/volume comparison for $symbol."
    }
    $captureBySymbol[$symbol] = $record
}

$quarantineBySymbol = @{}
foreach ($record in $quarantine) {
    $symbol = [string]$record.symbol
    if (-not $manifestBySymbol.ContainsKey($symbol)) { throw "Quarantine contains an unlisted symbol: $symbol." }
    $quarantineBySymbol[$symbol] = $true
    $rawResponseProperty = $record.PSObject.Properties['raw_response_base64']
    if ($null -ne $rawResponseProperty -and -not [string]::IsNullOrEmpty([string]$rawResponseProperty.Value)) {
        $rawBytes = [Convert]::FromBase64String([string]$rawResponseProperty.Value)
        if ((Get-Sha256Hex $rawBytes) -cne [string]$record.raw_response_sha256) {
            throw "Quarantined BSC raw-response SHA-256 does not verify for $symbol."
        }
        if ([string]$record.reason -match 'nonce|token') {
            throw "A request token was unexpectedly archived for quarantined symbol $symbol."
        }
    }
}

$unaccounted = @($manifest | Where-Object {
    -not $captureBySymbol.ContainsKey([string]$_.symbol) -and
    -not $quarantineBySymbol.ContainsKey([string]$_.symbol)
})
if ($unaccounted.Count -gt 0) {
    throw "Capture/quarantine records do not account for every target symbol; missing $($unaccounted.Count)."
}

$stageRows = [System.Collections.Generic.List[object]]::new()
foreach ($target in $manifest) {
    $symbol = [string]$target.symbol
    if (-not $captureBySymbol.ContainsKey($symbol)) { continue }
    $record = $captureBySymbol[$symbol]
    $payload = [ordered]@{
        request_url = 'https://www.bsc.com.vn/wp-admin/admin-ajax.php'
        source_page_url = [string]$record.source_page_url
        request = $record.request
        validation = $record.validation
        response = $record.source_response
        rows = @($record.normalized_row)
    }
    $payloadJson = ConvertTo-Json -InputObject $payload -Depth 30 -Compress
    if ($payloadJson.Contains("`t") -or $payloadJson.Contains("`r") -or $payloadJson.Contains("`n")) {
        throw "Normalized landing JSON contains an unescaped tab/newline for $symbol."
    }
    $stageRows.Add([pscustomobject]@{
        symbol = $symbol
        fetched_at = [string]$record.fetched_at
        payload_sha256 = [string]$record.raw_response_sha256
        raw_response_base64 = [string]$record.raw_response_base64
        payload_json = $payloadJson
    })
}

$resolvedStage = [System.IO.Path]::GetFullPath($StagePath)
$parent = Split-Path -Parent $resolvedStage
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$csvLines = $stageRows | ConvertTo-Csv -NoTypeInformation -Delimiter "`t"
[System.IO.File]::WriteAllLines($resolvedStage,$csvLines,$utf8NoBom)

$summary = [ordered]@{
    target_symbols = $manifest.Count
    matched_symbols = $capture.Count
    unique_quarantined_symbols = $quarantineBySymbol.Count
    matched_quarantined_overlap = @($captureBySymbol.Keys | Where-Object { $quarantineBySymbol.ContainsKey($_) }).Count
    materialized_candidates = $stageRows.Count
    input_capture_sha256 = Get-Sha256Hex ([System.IO.File]::ReadAllBytes([System.IO.Path]::GetFullPath($CapturePath)))
    landing_stage_sha256 = Get-Sha256Hex ([System.IO.File]::ReadAllBytes($resolvedStage))
}
[System.IO.File]::WriteAllText(
    (Join-Path $parent 'capture_summary.json'),
    (ConvertTo-Json -InputObject $summary -Depth 5),
    $utf8NoBom
)
Write-Output "Prepared $($stageRows.Count) exact-match BSC landing rows; quarantined target symbols remain excluded."
