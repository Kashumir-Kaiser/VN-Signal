param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'manifest.csv'),
    [string]$CapturePath = (Join-Path $PSScriptRoot 'capture.jsonl'),
    [string]$QuarantinePath = (Join-Path $PSScriptRoot 'quarantine.jsonl'),
    [int]$DelayMilliseconds = 700,
    [switch]$RetryTimedOutSymbols
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$baseUrl = 'https://www.bsc.com.vn'
$targetDate = '2019-01-02'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Write-JsonLine([string]$Path, [object]$Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 30 -Compress
    [System.IO.File]::AppendAllText($Path, $json + "`n", $utf8NoBom)
}

function Convert-CellNumber([string]$Text, [string]$FieldName) {
    $number = ($Text -replace '[,\s]', '')
    $parsed = [decimal]::Zero
    if (-not [decimal]::TryParse(
        $number,
        [System.Globalization.NumberStyles]::Number,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )) {
        throw "BSC $FieldName cell is not a decimal value."
    }
    return $parsed
}

function Convert-HistoryHtml([string]$Html) {
    $rows = [System.Text.RegularExpressions.Regex]::Matches(
        $Html,
        '<tr\b[^>]*>.*?</tr>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $dataRows = @()
    foreach ($rowMatch in $rows) {
        $cellMatches = [System.Text.RegularExpressions.Regex]::Matches(
            $rowMatch.Value,
            '<td\b[^>]*>(.*?)</td>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if ($cellMatches.Count -gt 0) {
            $cells = [System.Collections.Generic.List[string]]::new()
            foreach ($cellMatch in $cellMatches) {
                $plainText = [System.Text.RegularExpressions.Regex]::Replace($cellMatch.Groups[1].Value, '<[^>]+>', '')
                $plainText = [System.Net.WebUtility]::HtmlDecode(($plainText -replace '\s+', ' ').Trim())
                $cells.Add($plainText)
            }
            $dataRows += [pscustomobject]@{ html = $rowMatch.Value; cells = $cells.ToArray() }
        }
    }
    return $dataRows
}

if ($DelayMilliseconds -lt 500) {
    throw 'Use a request delay of at least 500 milliseconds.'
}
if (-not (Test-Path -LiteralPath $ManifestPath)) { throw 'Target manifest file is missing.' }
$allTargets = @(Import-Csv -LiteralPath $ManifestPath)
if ($allTargets.Count -ne 865 -or @($allTargets.symbol | Sort-Object -Unique).Count -ne 865) {
    throw "Expected 865 unique target symbols; found $($allTargets.Count) rows."
}
foreach ($target in $allTargets) {
    if ($target.trade_date -ne $targetDate -or
        $target.symbol -notmatch '^[A-Z0-9]{1,12}$' -or
        $target.vndirect_payload_sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Target manifest contains an invalid symbol, date, or VNDIRECT hash.'
    }
}
$manifest = $allTargets
if ($RetryTimedOutSymbols) {
    if (-not (Test-Path -LiteralPath $QuarantinePath)) { throw 'There are no quarantine records to retry.' }
    $timedOutSymbols = @(
        [System.IO.File]::ReadLines([System.IO.Path]::GetFullPath($QuarantinePath)) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object { $_.reason -match 'timed out|timeout' } |
            Select-Object -ExpandProperty symbol -Unique
    )
    $manifest = @($allTargets | Where-Object { $timedOutSymbols -contains $_.symbol })
    if ($manifest.Count -eq 0) { throw 'No timed-out BSC symbols are available for retry.' }
}
$captureDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($CapturePath))
New-Item -ItemType Directory -Force -Path $captureDirectory | Out-Null
foreach ($path in @($CapturePath,$QuarantinePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($path), '', $utf8NoBom)
    }
}

$completed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in [System.IO.File]::ReadLines([System.IO.Path]::GetFullPath($CapturePath))) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $prior = $line | ConvertFrom-Json
    if ($prior.status -ne 'MATCHED' -or $prior.trade_date -ne $targetDate -or
        -not $prior.raw_response_base64 -or -not $prior.raw_response_sha256) {
        throw 'Existing capture contains an incomplete or unvalidated record.'
    }
    $priorBytes = [Convert]::FromBase64String([string]$prior.raw_response_base64)
    if ((Get-Sha256Hex $priorBytes) -cne [string]$prior.raw_response_sha256) {
        throw 'Existing capture response hash does not match its archived bytes.'
    }
    if (-not $completed.Add([string]$prior.symbol)) {
        throw "Existing capture contains a duplicate symbol: $($prior.symbol)."
    }
}

$attemptTargetCount = $manifest.Count
if ($RetryTimedOutSymbols) {
    $manifest = @($manifest | Where-Object { -not $completed.Contains([string]$_.symbol) })
    $attemptTargetCount = $manifest.Count
    if ($attemptTargetCount -eq 0) {
        Write-Output 'No timed-out BSC symbols need retry; all are already in the validated capture.'
        return
    }
}

$pageUrl = "$baseUrl/en/historical-data/?mck=$($manifest[0].symbol)"
$page = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -SessionVariable bscSession -TimeoutSec 30
$nonceMatch = [System.Text.RegularExpressions.Regex]::Match($page.Content, '"security"\s*:\s*"([^"]+)"')
if (-not $nonceMatch.Success) { throw 'BSC public history page did not provide its form nonce.' }
$nonce = $nonceMatch.Groups[1].Value

$processed = 0
$matchedCount = $completed.Count
$quarantinedCount = 0
foreach ($target in $manifest) {
    $symbol = [string]$target.symbol
    if ($completed.Contains($symbol)) { continue }

    $fetchedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $referer = "$baseUrl/en/historical-data/?mck=$symbol"
    $body = @{
        action = 'filter_du_lieu_lich_su'
        mck = $symbol
        fromdate = $targetDate
        todate = $targetDate
        type_form = 'history'
        security = $nonce
        page = '1'
        items_per_page = '20'
    }

    $rawBytes = $null
    $responseJson = $null
    $responseHash = $null
    $httpStatus = $null
    $safeToArchive = $false
    try {
        $response = Invoke-WebRequest -Uri "$baseUrl/wp-admin/admin-ajax.php" -Method Post `
            -Body $body -WebSession $bscSession -UseBasicParsing -TimeoutSec 30 `
            -Headers @{ Referer = $referer; 'X-Requested-With' = 'XMLHttpRequest' }
        $httpStatus = [int]$response.StatusCode
        $rawBytes = [byte[]]$response.RawContentStream.ToArray()
        if ($rawBytes.Length -lt 2 -or $rawBytes.Length -gt 10485760) {
            throw 'BSC response body is outside the archival size bound.'
        }
        $rawText = [System.Text.Encoding]::UTF8.GetString($rawBytes).TrimStart([char]0xFEFF)
        if ($rawText.Contains($nonce)) {
            throw 'BSC response unexpectedly contains its request nonce; no response was archived.'
        }
        $safeToArchive = $true
        $responseJson = $rawText | ConvertFrom-Json
        $responseHash = Get-Sha256Hex $rawBytes
        if ([int]$response.StatusCode -ne 200 -or -not $responseJson.success -or
            -not $responseJson.data -or [string]::IsNullOrWhiteSpace([string]$responseJson.data.html)) {
            throw 'BSC did not return a successful history table.'
        }

        $dataRows = @(Convert-HistoryHtml ([string]$responseJson.data.html))
        if ($dataRows.Count -ne 1 -or $dataRows[0].cells.Count -ne 10) {
            throw "Expected exactly one 10-cell BSC history row; received $($dataRows.Count) row(s)."
        }
        $cells = $dataRows[0].cells
        $rowDate = [DateTime]::ParseExact(
            $cells[0], 'dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture
        ).ToString('yyyy-MM-dd')
        if ($rowDate -ne $targetDate) { throw 'BSC returned a row for the wrong date.' }

        $closeVnd = Convert-CellNumber $cells[1] 'close'
        $matchedVolume = Convert-CellNumber $cells[3] 'matched volume'
        $referenceVnd = Convert-CellNumber $cells[7] 'reference price'
        $ceilingVnd = Convert-CellNumber $cells[8] 'ceiling price'
        $floorVnd = Convert-CellNumber $cells[9] 'floor price'
        $localCloseVnd = [decimal]::Parse([string]$target.vndirect_close_thousand_vnd, [System.Globalization.CultureInfo]::InvariantCulture) * 1000
        $localVolume = [decimal]::Parse([string]$target.vndirect_volume_shares, [System.Globalization.CultureInfo]::InvariantCulture)
        $archivedCloseVnd = [decimal]::Parse([string]$target.archived_close, [System.Globalization.CultureInfo]::InvariantCulture) * 1000
        $archivedMatchedVolume = [decimal]::Parse([string]$target.archived_nm_volume, [System.Globalization.CultureInfo]::InvariantCulture)
        if ($closeVnd -le 0 -or $referenceVnd -le 0 -or $ceilingVnd -le 0 -or
            $floorVnd -le 0 -or $ceilingVnd -lt $floorVnd -or $matchedVolume -lt 0) {
            throw 'BSC close, volume, or source-reported limit bounds are invalid.'
        }
        if ($closeVnd -ne $localCloseVnd -or $closeVnd -ne $archivedCloseVnd -or
            $matchedVolume -ne $localVolume -or $matchedVolume -ne $archivedMatchedVolume) {
            throw 'BSC close or matched volume does not exactly match the archived VNDIRECT bar.'
        }

        $normalized = [ordered]@{
            code = $symbol
            trade_date = $rowDate
            close_price_vnd = $closeVnd.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            matched_volume_shares = $matchedVolume.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            reference_price_vnd = $referenceVnd.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            ceiling_price_vnd = $ceilingVnd.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            floor_price_vnd = $floorVnd.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            source_cells = @($cells)
            source_row_html = [string]$dataRows[0].html
        }
        $record = [ordered]@{
            status = 'MATCHED'
            symbol = $symbol
            trade_date = $rowDate
            source_page_url = $referer
            request = [ordered]@{
                action = 'filter_du_lieu_lich_su'
                mck = $symbol
                fromdate = $targetDate
                todate = $targetDate
                type_form = 'history'
                page = '1'
                items_per_page = '20'
            }
            fetched_at = $fetchedAt
            http_status = [int]$response.StatusCode
            validation = [ordered]@{
                vndirect_landing_id = [long]$target.vndirect_landing_id
                vndirect_source_row = [int]$target.vndirect_source_row
                vndirect_payload_sha256 = [string]$target.vndirect_payload_sha256
                exact_close_match = $true
                exact_matched_volume_match = $true
                bands_are_source_reported = $true
            }
            normalized_row = $normalized
            source_response = $responseJson
            raw_response_base64 = [Convert]::ToBase64String($rawBytes)
            raw_response_sha256 = $responseHash
        }
        Write-JsonLine $CapturePath $record
        [void]$completed.Add($symbol)
        $matchedCount++
    } catch {
        $quarantinedCount++
        $quarantine = [ordered]@{
            status = 'QUARANTINED'
            symbol = $symbol
            trade_date = $targetDate
            fetched_at = $fetchedAt
            http_status = $httpStatus
            reason = $_.Exception.Message
        }
        if ($safeToArchive -and $null -ne $rawBytes) {
            $quarantine.request = [ordered]@{
                action = 'filter_du_lieu_lich_su'
                mck = $symbol
                fromdate = $targetDate
                todate = $targetDate
                type_form = 'history'
                page = '1'
                items_per_page = '20'
            }
            $quarantine.source_response = $responseJson
            $quarantine.raw_response_base64 = [Convert]::ToBase64String($rawBytes)
            $quarantine.raw_response_sha256 = $responseHash
        }
        Write-JsonLine $QuarantinePath $quarantine
    }

    $processed++
    if ($processed % 25 -eq 0) {
        Write-Output "BSC date capture: processed=$processed accepted=$matchedCount quarantined=$quarantinedCount"
    }
    Start-Sleep -Milliseconds $DelayMilliseconds
}

Write-Output "BSC date capture finished: accepted=$matchedCount quarantined=$quarantinedCount total=$($manifest.Count)"
if ($RetryTimedOutSymbols -and $processed -ne $attemptTargetCount) {
    throw 'Timeout-retry accounting does not cover all selected symbols.'
}
if (-not $RetryTimedOutSymbols -and $matchedCount + $quarantinedCount -ne $allTargets.Count) {
    throw 'Capture accounting does not cover the target manifest; rerun to resume the remaining symbols.'
}
