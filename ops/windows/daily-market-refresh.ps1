[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stateRoot = Join-Path $env:LOCALAPPDATA 'VN-Signal'
$logRoot = Join-Path $stateRoot 'logs'
$credentialPath = Join-Path $stateRoot 'db-credential.xml'
$runStarted = Get-Date
$logFile = Join-Path $logRoot ("market-refresh-{0}.log" -f $runStarted.ToString('yyyy-MM-dd'))
$script:logFile = $logFile
$script:locationPushed = $false

function Write-RunLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss zzz} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
}

function Invoke-Vnpipe {
    param([Parameter(Mandatory)][string[]]$Arguments)
    Write-RunLog ("vnpipe " + ($Arguments -join ' '))
    $output = & $script:vnpipePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-RunLog ([string]$line)
    }
    if ($exitCode -ne 0) {
        throw "vnpipe exited with code $exitCode"
    }
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Write-RunLog 'Starting VCI canonical and VNDIRECT source refresh.'

try {
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
        throw "Encrypted PostgreSQL credential is missing at $credentialPath"
    }
    $dbCredential = Import-Clixml -LiteralPath $credentialPath
    $dbPassword = $dbCredential.GetNetworkCredential().Password
    $dbUser = [Uri]::EscapeDataString($dbCredential.UserName)
    $escapedPassword = [Uri]::EscapeDataString($dbPassword)
    $env:DATABASE_URL = 'postgres://' + $dbUser + ':' + $escapedPassword + '@127.0.0.1:5432/vnsignal?sslmode=disable'
    $env:PGPASSWORD = $dbPassword
    $env:VNPIPE_PYTHON = Join-Path $repoRoot '.venv\Scripts\python.exe'
    $env:VNSTOCK_HOME = Join-Path $env:USERPROFILE '.vnstock'
    $env:VNPIPE_CONFIG = Join-Path $repoRoot 'config\default.toml'
    $env:VNPIPE_DISABLE_LIVE = '0'

    if (-not (Test-Path -LiteralPath $env:VNPIPE_PYTHON -PathType Leaf)) {
        throw "Configured Python interpreter is missing at $env:VNPIPE_PYTHON"
    }
    if (-not (Test-Path -LiteralPath $env:VNSTOCK_HOME -PathType Container)) {
        throw "Registered vnstock profile directory is missing at $env:VNSTOCK_HOME"
    }

    $psqlCommand = Get-Command psql.exe -CommandType Application -ErrorAction Stop
    $dbCheck = & $psqlCommand.Source -h 127.0.0.1 -U $dbCredential.UserName -d vnsignal -w -Atc 'SELECT 1' 2>&1
    $dbExitCode = $LASTEXITCODE
    if ($dbExitCode -ne 0 -or ($dbCheck -join '').Trim() -ne '1') {
        throw 'Local PostgreSQL readiness check failed.'
    }
    Write-RunLog 'Local PostgreSQL connection is ready.'

    $goCommand = Get-Command go.exe -CommandType Application -ErrorAction Stop
    $binRoot = Join-Path $stateRoot 'bin'
    New-Item -ItemType Directory -Path $binRoot -Force | Out-Null
    $script:vnpipePath = Join-Path $binRoot 'vnpipe.exe'
    Write-RunLog 'Building the PostgreSQL-enabled local vnpipe executable.'
    $buildOutput = & $goCommand.Source -C (Join-Path $repoRoot 'go') build -tags postgres -o $script:vnpipePath ./cmd/vnpipe 2>&1
    $buildExitCode = $LASTEXITCODE
    foreach ($line in $buildOutput) {
        Write-RunLog ([string]$line)
    }
    if ($buildExitCode -ne 0) {
        throw "vnpipe build exited with code $buildExitCode"
    }

    Push-Location (Join-Path $repoRoot 'go')
    $script:locationPushed = $true
    $today = (Get-Date).Date
    $todayText = $today.ToString('yyyy-MM-dd')
    $fromText = $today.AddDays(-14).ToString('yyyy-MM-dd')
    $nextMonth = $today.AddMonths(1)
    $monthEnd = $nextMonth.AddDays(-$nextMonth.Day)
    # Counting every remaining calendar day is an upper bound on trading sessions,
    # so the monthly quota allocation stays conservative even around holidays.
    $quotaDays = [Math]::Max(1, ($monthEnd - $today).Days + 1)
    $runDirectory = Join-Path (Join-Path $stateRoot 'reports') ($today.ToString('yyyy-MM-dd') + '-' + $runStarted.ToString('HHmmss'))
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

    $vciSucceeded = $false
    try {
        Invoke-Vnpipe @(
            'probe', '--active', '--routes', 'equity_list,equity_ohlcv',
            '--trading-days', "$quotaDays",
            '--from', $fromText, '--to', $todayText,
            '--out', $runDirectory
        )

        $reportPath = Join-Path $runDirectory ($todayText + '.json')
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw "Active VCI route probe did not save its report at $reportPath"
        }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if (-not $report.active -or -not $report.routes.equity_ohlcv.available -or -not $report.routes.equity_list.available) {
            throw 'The active VCI listing and equity OHLCV probes did not both verify their routes.'
        }

        Invoke-Vnpipe @('import-listings', '--probe', $reportPath)
        Invoke-Vnpipe @(
            'backfill', '--active', '--probe', $reportPath,
            '--from', $fromText, '--to', $todayText,
            '--days', "$quotaDays", '--max-calls', '2000', '--rotate-daily'
        )
        $vciSucceeded = $true
        Write-RunLog ("Completed VCI canonical refresh window {0} through {1}." -f $fromText, $todayText)
    }
    catch {
        Write-RunLog ("VCI refresh failed; proceeding to the separate VNDIRECT series: " + $_.Exception.Message)
    }

    $vndirectSucceeded = $false
    try {
        Invoke-Vnpipe @(
            'backfill-vndirect', '--active',
            '--from', $fromText, '--to', $todayText,
            '--max-calls', '2000', '--pace', '500ms'
        )
        $vndirectSucceeded = $true
        Write-RunLog ("Completed source-keyed VNDIRECT refresh window {0} through {1}." -f $fromText, $todayText)
    }
    catch {
        Write-RunLog ("VNDIRECT refresh failed: " + $_.Exception.Message)
    }
    if (-not $vciSucceeded -and -not $vndirectSucceeded) {
        throw 'Both the VCI canonical refresh and the separate VNDIRECT refresh failed.'
    }
    exit 0
}
catch {
    Write-RunLog ("FAILED: " + $_.Exception.Message)
    exit 1
}
finally {
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    if ($script:locationPushed) {
        Pop-Location
    }
}
