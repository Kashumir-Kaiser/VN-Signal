[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'VN-Signal'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$credential = Get-Credential -UserName 'postgres' -Message 'Enter the local VN-Signal PostgreSQL password. Windows will encrypt it for this user account.'
$credential | Export-Clixml -LiteralPath (Join-Path $stateRoot 'db-credential.xml')
Write-Output 'Saved an encrypted, user-bound PostgreSQL credential for the scheduled refresh.'
