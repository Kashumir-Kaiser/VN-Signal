$ErrorActionPreference='Stop'
Set-Location -LiteralPath 'C:\Users\HP\VN-Signal'
$folder='docs/evidence/phase2/spi_transfer_sources_20261024'
$manifest=Import-Csv "$folder/manifest.csv"
$expectedFiles=@('spi_hnx_delisting_notice_2642_2025-06-13.pdf','spi_vsdc_hnx_upcom_transfer_2025-06-19.html','spi_hnx_upcom_profile.html')
if($manifest.Count -ne 3 -or @($manifest.local_file | Sort-Object -Unique).Count -ne 3){throw 'Expected exactly three distinct source records'}
if((Compare-Object ($manifest.local_file | Sort-Object) ($expectedFiles | Sort-Object)).Count -ne 0){throw 'Manifest file scope differs from the reviewed packet'}
$stage=@(foreach($record in $manifest){
 if($record.symbol -cne 'SPI'){throw 'Ticker mismatch'}
 if($record.source -notin @('hnx','vsdc')){throw 'Unknown source'}
 $metadata=[ordered]@{
  source_url=$record.source_url
  local_file=$record.local_file
  source_attribution=if($record.source -eq 'vsdc'){'Vietnam Securities Depository and Clearing Corporation (VSDC)'}else{'Hanoi Stock Exchange (HNX)'}
  capture_time_basis='UTC timestamp recorded at local file capture; see source manifest'
  document_date=if($record.document_date){$record.document_date}else{$null}
  claim_last_hnx_trade_date=if($record.claim_last_hnx_trade_date){$record.claim_last_hnx_trade_date}else{$null}
  claim_delisting_effective_date=if($record.claim_delisting_effective_date){$record.claim_delisting_effective_date}else{$null}
  claim_first_upcom_trade_date=if($record.claim_first_upcom_trade_date){$record.claim_first_upcom_trade_date}else{$null}
  claim_custody_transfer_effective_date=if($record.claim_custody_transfer_effective_date){$record.claim_custody_transfer_effective_date}else{$null}
  source_claim=$record.source_claim
  source_limitation=$record.source_limitation
 }
 $path=Join-Path $folder $record.local_file
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing source file: $($record.local_file)"}
 if((Get-Item -LiteralPath $path).Length -ne [long]$record.payload_size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.payload_sha256){throw "Source bytes differ from manifest: $($record.local_file)"}
 if((Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") -ne $record.captured_at_utc){throw "Capture timestamp differs from manifest: $($record.local_file)"}
 [pscustomobject]@{symbol=$record.symbol;source=$record.source;fetched_at=$record.captured_at_utc;source_url=$record.source_url;local_file=$record.local_file;payload_sha256=$record.payload_sha256;payload_size=$record.payload_size;metadata_json=($metadata|ConvertTo-Json -Compress);body_b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Get-Location) $path)))}
})
$stage|Export-Csv -NoTypeInformation "$folder/landing_stage.csv"
function Literal($value){return "'"+([string]$value).Replace("'","''")+"'"}
$tuples=($stage|ForEach-Object {'('+((@($_.symbol,$_.source,$_.fetched_at,$_.source_url,$_.local_file,$_.payload_sha256,$_.payload_size,$_.metadata_json)|ForEach-Object {Literal $_}) -join ',')+')'}) -join ",`n"
$template=Get-Content -Raw "$folder/import_template.sql"
[IO.File]::WriteAllText((Join-Path (Get-Location) "$folder/import_landings_reportclone.sql"),$template.Replace('__EXPECTED__',$tuples),[Text.UTF8Encoding]::new($false))
Write-Output "Prepared $($stage.Count) SPI source records; verified size, hash, capture timestamp. No database connection was made."
