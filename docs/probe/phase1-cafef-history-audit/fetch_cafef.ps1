$ErrorActionPreference = 'Stop'

$auditDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rawDir = Join-Path $auditDir 'raw'
if (-not (Test-Path -LiteralPath $rawDir -PathType Container)) {
    New-Item -ItemType Directory -Path $rawDir | Out-Null
}

$symbols = @('CDG','GGG','HPI','NAS','SBD','SDD','SHC','SNC','SPC','SVG','TNB','VFC','VNI','VNX','XMC','XPH')
$expected = Import-Csv (Join-Path (Split-Path -Parent $auditDir) 'phase1-partial-audit/issue-coverage.csv') |
    Select-Object -ExpandProperty symbol -Unique | Sort-Object
$actual = $symbols | Sort-Object
if (($expected -join ',') -ne ($actual -join ',')) {
    throw "CafeF audit symbol list does not match issue-coverage.csv: $($expected -join ',')"
}

$periods = @(
    [pscustomobject]@{ Year = 2018; Start = '10/01/2018'; End = '12/31/2018' }
)
foreach ($year in 2019..2025) {
    $periods += [pscustomobject]@{ Year = $year; Start = "01/01/$year"; End = "12/31/$year" }
}
$periods += [pscustomobject]@{ Year = 2026; Start = '01/01/2026'; End = '10/16/2026' }

$manifestPath = Join-Path $auditDir 'manifest.csv'
$manifest = [System.Collections.Generic.List[object]]::new()
$total = $symbols.Count * $periods.Count
$done = 0

foreach ($symbol in $symbols) {
    $exchange = if ($symbol -eq 'SPC') { 'HNX' } else { 'UPCOM' }
    foreach ($period in $periods) {
        $done++
        $name = "$symbol-$($period.Year).xlsx"
        $path = Join-Path $rawDir $name
        $tmp = "$path.download"
        $status = 'OK'
        $errorText = ''

        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($path)
                if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
                    throw "Existing artifact is not an XLSX ZIP file: $name"
                }
                $status = 'EXISTING'
            } else {
                $start = [Uri]::EscapeDataString($period.Start)
                $end = [Uri]::EscapeDataString($period.End)
                $url = "https://cafef.vn/du-lieu/Ajax/PageNew/DataHistory/PriceHistoryExport.ashx?ExchangeType=$exchange&Symbol=$symbol&StartDate=$start&EndDate=$end"
                Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 45 -Headers @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0 Safari/537.36'
                    'Referer' = 'https://cafef.vn/du-lieu/lich-su-giao-dich/'
                } -OutFile $tmp | Out-Null
                $bytes = [System.IO.File]::ReadAllBytes($tmp)
                if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
                    throw "CafeF did not return an XLSX artifact for $symbol/$($period.Year)"
                }
                Move-Item -LiteralPath $tmp -Destination $path
            }

            $item = Get-Item -LiteralPath $path
            $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $manifest.Add([pscustomobject]@{
                symbol = $symbol; exchange = $exchange; year = $period.Year
                start_date = $period.Start; end_date = $period.End
                status = $status; bytes = $item.Length; sha256 = $sha
                fetched_utc = [DateTime]::UtcNow.ToString('o'); error = ''
            })
        } catch {
            if (Test-Path -LiteralPath $tmp -PathType Leaf) {
                Remove-Item -LiteralPath $tmp
            }
            $errorText = $_.Exception.Message
            $manifest.Add([pscustomobject]@{
                symbol = $symbol; exchange = $exchange; year = $period.Year
                start_date = $period.Start; end_date = $period.End
                status = 'ERROR'; bytes = 0; sha256 = ''
                fetched_utc = [DateTime]::UtcNow.ToString('o'); error = $errorText
            })
        }

        if ($done % $periods.Count -eq 0) {
            $manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8
            Write-Output ("{0}/{1} {2} {3}" -f $done, $total, $symbol, $(if ($errorText) { "ERROR: $errorText" } else { 'saved' }))
        }
        Start-Sleep -Milliseconds 350
    }
}

$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8
$ok = @($manifest | Where-Object { $_.status -in @('OK','EXISTING') }).Count
$errors = @($manifest | Where-Object { $_.status -eq 'ERROR' }).Count
Write-Output "Complete: $ok/$total valid XLSX artifacts; errors=$errors; manifest=$manifestPath"
