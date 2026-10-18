$ErrorActionPreference = 'Stop'

$baseUrl = 'https://www.bsc.com.vn'
$startDate = '2018-10-01'
$endDate = '2026-10-16'
$pageSize = 1000
$symbols = @('CDG', 'GGG', 'HPI', 'NAS', 'SBD', 'SDD', 'SHC', 'SNC', 'SPC', 'SVG', 'TNB', 'VFC', 'VNI', 'VNX', 'XMC', 'XPH')
$outDir = Join-Path $PSScriptRoot '..\phase1-bsc-history-audit'
$rawDir = Join-Path $outDir 'raw'
New-Item -ItemType Directory -Force -Path $rawDir | Out-Null

$pageUrl = "$baseUrl/en/historical-data/?mck=$($symbols[0])"
$page = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -SessionVariable bscSession
$nonce = [regex]::Match($page.Content, '"security":"([^"]+)"').Groups[1].Value
if (-not $nonce) { throw 'BSC public history page did not provide its form nonce.' }

$manifest = [System.Collections.Generic.List[object]]::new()
$bars = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$pageNumber = 1

foreach ($symbol in $symbols) {
    $firstPage = $true
    $totalPages = 1
    for ($pageNumber = 1; $pageNumber -le $totalPages; $pageNumber++) {
        $referer = "$baseUrl/en/historical-data/?mck=$symbol"
        $body = @{
            action = 'filter_du_lieu_lich_su'
            mck = $symbol
            fromdate = $startDate
            todate = $endDate
            type_form = 'history'
            security = $nonce
            page = [string]$pageNumber
            items_per_page = [string]$pageSize
        }
        $response = Invoke-WebRequest -Uri "$baseUrl/wp-admin/admin-ajax.php" -Method Post `
            -Body $body -WebSession $bscSession -UseBasicParsing `
            -Headers @{ Referer = $referer; 'X-Requested-With' = 'XMLHttpRequest' }
        $result = $response.Content | ConvertFrom-Json
        if ($response.StatusCode -ne 200 -or -not $result.success -or -not $result.data) {
            throw "${symbol} page ${pageNumber}: BSC returned an unsuccessful history response."
        }
        if ($firstPage) {
            $totalPages = [int]$result.data.total_pages
            if ($totalPages -lt 1 -or $totalPages -gt 10) { throw "${symbol}: unexpected BSC page count $totalPages." }
            $firstPage = $false
        } elseif ([int]$result.data.total_pages -ne $totalPages) {
            throw "${symbol} page ${pageNumber}: total page count changed during retrieval."
        }

        $html = [string]$result.data.html
        $tableRows = [regex]::Matches($html, '<tr\b[^>]*>(.*?)</tr>', 'Singleline')
        $pageBars = 0
        $pageDates = [System.Collections.Generic.List[string]]::new()
        foreach ($tableRow in $tableRows) {
            $cells = [regex]::Matches($tableRow.Groups[1].Value, '<td[^>]*>(.*?)</td>', 'Singleline') |
                ForEach-Object {
                    $plain = [regex]::Replace($_.Groups[1].Value, '<[^>]+>', '')
                    [System.Net.WebUtility]::HtmlDecode(($plain -replace '\s+', ' ').Trim())
                }
            if ($cells.Count -ne 10) { throw "${symbol} page ${pageNumber}: history row has $($cells.Count) cells, expected 10." }
            $date = [datetime]::ParseExact($cells[0], 'dd/MM/yyyy', [cultureinfo]::InvariantCulture).ToString('yyyy-MM-dd')
            if ($date -lt $startDate -or $date -gt $endDate) { throw "${symbol} page ${pageNumber}: row date $date is out of range." }
            $key = "$symbol|$date"
            if (-not $seen.Add($key)) { throw "${symbol}: duplicate date $date returned across BSC pages." }
            $matchedVolume = [int64]($cells[3] -replace ',', '')
            $matchedValue = [decimal]::Parse(($cells[4] -replace ',', ''), [cultureinfo]::InvariantCulture)
            $negotiatedVolume = [int64]($cells[5] -replace ',', '')
            $negotiatedValue = [decimal]::Parse(($cells[6] -replace ',', ''), [cultureinfo]::InvariantCulture)
            if ($matchedVolume -lt 0 -or $matchedValue -lt 0 -or $negotiatedVolume -lt 0 -or $negotiatedValue -lt 0) {
                throw "${symbol} ${date}: BSC returned negative activity fields."
            }
            $bars.Add([pscustomobject]@{
                symbol = $symbol
                trade_date = $date
                close_price_thousand_vnd = $cells[1]
                matched_volume = $matchedVolume
                matched_value_million_vnd = $matchedValue
                negotiated_volume = $negotiatedVolume
                negotiated_value_million_vnd = $negotiatedValue
                open_price_thousand_vnd = $cells[7]
                ceiling_price_thousand_vnd = $cells[8]
                floor_price_thousand_vnd = $cells[9]
            })
            $pageDates.Add($date)
            $pageBars++
        }

        $rawPath = Join-Path $rawDir ("{0}-page-{1:D2}.json" -f $symbol, $pageNumber)
        [System.IO.File]::WriteAllText($rawPath, $response.Content, [System.Text.UTF8Encoding]::new($false))
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($response.Content)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $manifest.Add([pscustomobject]@{
            symbol = $symbol
            from_date = $startDate
            to_date = $endDate
            page = $pageNumber
            page_size = $pageSize
            total_pages = $totalPages
            row_count = $pageBars
            first_date = ($pageDates | Sort-Object | Select-Object -First 1)
            last_date = ($pageDates | Sort-Object | Select-Object -Last 1)
            http_status = [int]$response.StatusCode
            response_sha256_utf8 = $digest
            raw_file = "raw/$(Split-Path -Leaf $rawPath)"
        })
        Write-Output "BSC history: $symbol page $pageNumber/$totalPages rows=$pageBars"
        Start-Sleep -Milliseconds 700
    }
}

$expected = @{}
foreach ($row in @(
    @{ symbol='CDG'; date='2022-08-15'; matched=0; negotiated=0 },
    @{ symbol='GGG'; date='2021-08-31'; matched=0; negotiated=0 },
    @{ symbol='HPI'; date='2022-07-08'; matched=0; negotiated=0 },
    @{ symbol='NAS'; date='2021-11-23'; matched=0; negotiated=0 },
    @{ symbol='SBD'; date='2021-08-04'; matched=0; negotiated=0 },
    @{ symbol='SDD'; date='2019-11-18'; matched=0; negotiated=0 },
    @{ symbol='SHC'; date='2022-10-05'; matched=0; negotiated=0 },
    @{ symbol='SNC'; date='2023-01-19'; matched=0; negotiated=0 },
    @{ symbol='SPC'; date='2020-12-08'; matched=0; negotiated=0 },
    @{ symbol='SVG'; date='2020-07-01'; matched=0; negotiated=0 },
    @{ symbol='TNB'; date='2022-04-08'; matched=0; negotiated=0 },
    @{ symbol='VFC'; date='2021-09-20'; matched=0; negotiated=0 },
    @{ symbol='VNI'; date='2021-12-14'; matched=0; negotiated=0 },
    @{ symbol='VNX'; date='2023-03-30'; matched=0; negotiated=0 },
    @{ symbol='XMC'; date='2020-03-13'; matched=0; negotiated=0 },
    @{ symbol='XPH'; date='2022-12-20'; matched=0; negotiated=0 },
    @{ symbol='CDG'; date='2025-05-13'; matched=100; negotiated=0 },
    @{ symbol='NAS'; date='2020-10-15'; matched=80; negotiated=0 },
    @{ symbol='VFC'; date='2026-07-03'; matched=1; negotiated=0 },
    @{ symbol='SNC'; date='2026-10-15'; matched=71; negotiated=0 },
    @{ symbol='VNX'; date='2026-01-29'; matched=0; negotiated=15100 },
    @{ symbol='VNX'; date='2026-01-30'; matched=0; negotiated=4900 },
    @{ symbol='VNX'; date='2026-02-12'; matched=0; negotiated=4900 }
)) { $expected["$($row.symbol)|$($row.date)"] = $row }
foreach ($key in $expected.Keys) {
    $actual = $bars | Where-Object { "$($_.symbol)|$($_.trade_date)" -eq $key }
    if ($actual.Count -ne 1 -or $actual[0].matched_volume -ne $expected[$key].matched -or
        $actual[0].negotiated_volume -ne $expected[$key].negotiated) {
        throw "BSC history does not match archived control $key."
    }
}

$manifestPath = Join-Path $outDir 'manifest.csv'
$dataPath = Join-Path $outDir 'daily-activity.csv'
$manifest | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $manifestPath
$bars | Sort-Object symbol,trade_date | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $dataPath
Write-Output "Validated $($bars.Count) BSC session rows across $($manifest.Count) archived pages and $($expected.Count) HNX-verified volume controls."
