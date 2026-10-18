$ErrorActionPreference = 'Stop'

$baseUrl = 'https://www.bsc.com.vn'
$pageUrl = "$baseUrl/en/historical-data/?mck=CDG"
$page = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -SessionVariable bscSession
$nonce = [regex]::Match($page.Content, '"security":"([^"]+)"').Groups[1].Value
if (-not $nonce) { throw 'BSC public history page did not provide its form nonce.' }

$controls = @(
    @{ symbol = 'CDG'; date = '2022-08-15' },
    @{ symbol = 'GGG'; date = '2021-08-31' },
    @{ symbol = 'HPI'; date = '2022-07-08' },
    @{ symbol = 'NAS'; date = '2021-11-23' },
    @{ symbol = 'SBD'; date = '2021-08-04' },
    @{ symbol = 'SDD'; date = '2019-11-18' },
    @{ symbol = 'SHC'; date = '2022-10-05' },
    @{ symbol = 'SNC'; date = '2023-01-19' },
    @{ symbol = 'SPC'; date = '2020-12-08' },
    @{ symbol = 'SVG'; date = '2020-07-01' },
    @{ symbol = 'TNB'; date = '2022-04-08' },
    @{ symbol = 'VFC'; date = '2021-09-20' },
    @{ symbol = 'VNI'; date = '2021-12-14' },
    @{ symbol = 'VNX'; date = '2023-03-30' },
    @{ symbol = 'XMC'; date = '2020-03-13' },
    @{ symbol = 'XPH'; date = '2022-12-20' }
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
    $referer = "$baseUrl/en/historical-data/?mck=$($control.symbol)"
    $response = Invoke-WebRequest -Uri "$baseUrl/wp-admin/admin-ajax.php" -Method Post `
        -Body $body -WebSession $bscSession -UseBasicParsing `
        -Headers @{ Referer = $referer; 'X-Requested-With' = 'XMLHttpRequest' }
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
    $actualDate = [datetime]::ParseExact($cells[0], 'dd/MM/yyyy', [cultureinfo]::InvariantCulture).ToString('yyyy-MM-dd')
    $matchedVolume = [int64]($cells[3] -replace ',', '')
    $matchedValue = [decimal]($cells[4] -replace ',', '')
    $negotiatedVolume = [int64]($cells[5] -replace ',', '')
    $negotiatedValue = [decimal]($cells[6] -replace ',', '')
    if ($actualDate -ne $control.date -or $matchedVolume -ne 0 -or $matchedValue -ne 0 -or
        $negotiatedVolume -ne 0 -or $negotiatedValue -ne 0) {
        throw "$($control.symbol) $($control.date): BSC row conflicts with the archived HNX zero-total control."
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($response.Content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    [pscustomobject]@{
        symbol = $control.symbol
        trade_date = $control.date
        source_url = $referer
        http_status = [int]$response.StatusCode
        row_count = 1
        matched_volume = $matchedVolume
        matched_value_million_vnd = $cells[4]
        negotiated_volume = $negotiatedVolume
        negotiated_value_million_vnd = $cells[6]
        response_sha256_utf8 = $digest
        raw_response = $response.Content
    }
    Start-Sleep -Milliseconds 700
}

$outputPath = Join-Path $PSScriptRoot 'bsc-hnx-sample-20261019.json'
$rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Output "Validated and archived $($rows.Count) BSC zero-total controls from the exact HNX sample: $outputPath"
