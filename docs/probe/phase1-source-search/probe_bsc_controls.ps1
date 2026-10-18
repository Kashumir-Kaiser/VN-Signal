$ErrorActionPreference = 'Stop'
$baseUrl = 'https://www.bsc.com.vn'
$pageUrl = "$baseUrl/en/historical-data/?mck=CDG"
$page = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -SessionVariable bscSession
$nonce = [regex]::Match($page.Content, '"security":"([^"]+)"').Groups[1].Value
if (-not $nonce) { throw 'BSC public history page did not provide its form nonce.' }

$controls = @(
    @{ symbol = 'CDG'; date = '2025-05-13'; matched = 100; negotiated = 0 },
    @{ symbol = 'NAS'; date = '2020-10-15'; matched = 80; negotiated = 0 },
    @{ symbol = 'VFC'; date = '2026-07-03'; matched = 1; negotiated = 0 },
    @{ symbol = 'SNC'; date = '2026-10-15'; matched = 71; negotiated = 0 },
    @{ symbol = 'VNX'; date = '2026-01-29'; matched = 0; negotiated = 15100 },
    @{ symbol = 'VNX'; date = '2026-01-30'; matched = 0; negotiated = 4900 },
    @{ symbol = 'VNX'; date = '2026-02-12'; matched = 0; negotiated = 4900 }
)

$rows = foreach ($control in $controls) {
    $body = @{
        action = 'filter_du_lieu_lich_su'
        mck = $control.symbol
        fromdate = $control.date
        todate = $control.date
        type_form = 'history'
        security = $nonce
        page = '1'
        items_per_page = '20'
    }
    $response = Invoke-WebRequest -Uri "$baseUrl/wp-admin/admin-ajax.php" -Method Post `
        -Body $body -WebSession $bscSession -UseBasicParsing `
        -Headers @{ Referer = "$baseUrl/en/historical-data/?mck=$($control.symbol)"; 'X-Requested-With' = 'XMLHttpRequest' }
    $result = $response.Content | ConvertFrom-Json
    if ($response.StatusCode -ne 200 -or -not $result.success) {
        throw "$($control.symbol) $($control.date): BSC returned no history row."
    }
    $cells = [regex]::Matches([string]$result.data.html, '<td[^>]*>(.*?)</td>', 'Singleline') |
        ForEach-Object {
            $plain = [regex]::Replace($_.Groups[1].Value, '<[^>]+>', '')
            [System.Net.WebUtility]::HtmlDecode(($plain -replace '\s+', ' ').Trim())
        }
    if ($cells.Count -ne 10) { throw "$($control.symbol) $($control.date): expected 10 history cells, got $($cells.Count)." }
    $matchedVolume = [int64]($cells[3] -replace ',', '')
    $negotiatedVolume = [int64]($cells[5] -replace ',', '')
    if ($matchedVolume -ne $control.matched -or $negotiatedVolume -ne $control.negotiated) {
        throw "$($control.symbol) $($control.date): volume controls differ from expected HNX interpretation."
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($response.Content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    [pscustomobject]@{
        symbol = $control.symbol
        trade_date = $control.date
        source_url = "$baseUrl/en/historical-data/?mck=$($control.symbol)"
        http_status = [int]$response.StatusCode
        matched_volume = $matchedVolume
        matched_value_million_vnd = $cells[4]
        negotiated_volume = $negotiatedVolume
        negotiated_value_million_vnd = $cells[6]
        close_price_thousand_vnd = $cells[1]
        open_price_thousand_vnd = $cells[7]
        ceiling_price_thousand_vnd = $cells[8]
        floor_price_thousand_vnd = $cells[9]
        response_sha256_utf8 = $digest
        raw_response = $response.Content
    }
}

$outputPath = Join-Path $PSScriptRoot 'bsc-controls-20261019.json'
$rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Output "Validated and archived $($rows.Count) targeted BSC history controls: $outputPath"
