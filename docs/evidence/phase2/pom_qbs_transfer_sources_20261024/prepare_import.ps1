$ErrorActionPreference='Stop'
Set-Location -LiteralPath 'C:\Users\HP\VN-Signal'
$folder='docs/evidence/phase2/pom_qbs_transfer_sources_20261024'
$stage=@(foreach($record in Import-Csv "$folder/manifest.csv"){
 $ticker=$record.local_file.Substring(0,3).ToUpperInvariant()
 if($ticker -notin @('POM','QBS')){throw 'Unknown ticker'}
 $source=if($record.local_file -like '*hose_delisting*'){'cafef'}elseif($record.local_file -like '*hnx*'){'hnx'}elseif($record.local_file -like '*vsdc*'){'vsdc'}else{throw 'Unknown source document'}
 $metadata=[ordered]@{source_url=$record.source_url;local_file=$record.local_file;capture_time_basis='actual HTTP capture UTC recorded in source manifest';source_attribution='';document_date=$null;last_hose_trade_date=$null;delisting_effective_date=$null;first_upcom_trade_date=$null;custody_transfer_effective_date=$null;evidence_claim=''}
 switch($source){
  cafef {$metadata.source_attribution='Ho Chi Minh Stock Exchange (HOSE), original decision carried by CafeF';$metadata.document_date='2024-04-10';$metadata.last_hose_trade_date='2024-05-09';$metadata.delisting_effective_date='2024-05-10';$metadata.evidence_claim='Signed ticker-specific HOSE decision; page 2 gives final HOSE trade, page 1 gives delisting effective date.'}
  hnx {$metadata.source_attribution='Hanoi Stock Exchange (HNX)';$metadata.first_upcom_trade_date='2024-05-23';$metadata.evidence_claim='Current official issuer profile records historical first UPCoM trading date; contemporaneous publication date is not established.'}
  vsdc {$metadata.source_attribution='Vietnam Securities Depository and Clearing Corporation (VSDC)';$metadata.document_date='2024-04-16';$metadata.custody_transfer_effective_date='2024-05-14';$metadata.evidence_claim='QBS custody transfer from HOSE to UPCoM, citing HOSE decision 209; does not establish final or first trading date.'}
 }
 $path=Join-Path $folder $record.local_file
 if((Get-Item -LiteralPath $path).Length -ne [long]$record.payload_size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.payload_sha256){throw 'Source bytes differ from manifest'}
 [pscustomobject]@{symbol=$ticker;source=$source;fetched_at=$record.captured_at_utc;source_url=$record.source_url;local_file=$record.local_file;payload_sha256=$record.payload_sha256;payload_size=$record.payload_size;metadata_json=($metadata|ConvertTo-Json -Compress);body_b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Get-Location) $path)))}
})
if($stage.Count -ne 5){throw 'Expected five sources'}
$stage|Export-Csv -NoTypeInformation "$folder/landing_stage.csv"
function Literal($value){return "'"+([string]$value).Replace("'","''")+"'"}
$tuples=($stage|ForEach-Object {'('+((@($_.symbol,$_.source,$_.fetched_at,$_.source_url,$_.local_file,$_.payload_sha256,$_.payload_size,$_.metadata_json)|ForEach-Object {Literal $_}) -join ',')+')'}) -join ",`n"
$template=Get-Content -Raw "$folder/import_template.sql"
[IO.File]::WriteAllText((Join-Path (Get-Location) "$folder/import_landings_reportclone.sql"),$template.Replace('__EXPECTED__',$tuples),[Text.UTF8Encoding]::new($false))
