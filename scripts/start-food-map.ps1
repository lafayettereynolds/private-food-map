param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('development', 'production')]
  [string]$Environment
)

$ErrorActionPreference = 'Stop'

$projectDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$isProduction = $Environment -eq 'production'
$port = if ($isProduction) { 4173 } else { 5173 }
$appUrl = "http://localhost:$port/"
$healthUrl = "http://127.0.0.1:$port/"
$runtimeDependencies = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies'
$bundledPnpmExecutable = Join-Path $runtimeDependencies 'bin\fallback\pnpm.cmd'
$bundledNodeDirectory = Join-Path $runtimeDependencies 'node\bin'
$pnpmCommand = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
$pnpmExecutable = if ($pnpmCommand) { $pnpmCommand.Source } else { $bundledPnpmExecutable }
$nodeDirectory = if ($nodeCommand) { Split-Path -Parent $nodeCommand.Source } else { $bundledNodeDirectory }
$pnpmProjectArguments = @()

function Show-LauncherMessage([string]$message) {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show($message, 'Taste Map', 'OK', 'Information') | Out-Null
}

function Test-PortInUse {
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $asyncResult = $client.BeginConnect('127.0.0.1', $port, $null, $null)
    return $asyncResult.AsyncWaitHandle.WaitOne(500) -and $client.Connected
  }
  catch {
    return $false
  }
  finally {
    $client.Dispose()
  }
}

function Test-TasteMapReady {
  try {
    # Windows PowerShell 5 may spend several seconds resolving localhost over
    # IPv6 even though Vite listens on IPv4. Use the explicit loopback address
    # for readiness checks while keeping the user-facing URL unchanged.
    $response = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 2
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch '<title>Taste Map') {
      return $false
    }
    if ($isProduction) {
      return $response.Content -match '/assets/' -and $response.Content -notmatch '/src/main.tsx'
    }
    return $response.Content -match '/src/main.tsx'
  }
  catch {
    return $false
  }
}

function Test-ProductionBuildCurrent {
  $buildIndex = Join-Path $projectDirectory 'dist\index.html'
  if (-not (Test-Path -LiteralPath $buildIndex)) {
    return $false
  }
  $buildTime = (Get-Item -LiteralPath $buildIndex).LastWriteTimeUtc
  $inputFiles = @()
  $inputFiles += Get-ChildItem -LiteralPath (Join-Path $projectDirectory 'src') -Recurse -File
  $inputFiles += Get-Item -LiteralPath (Join-Path $projectDirectory 'index.html')
  $inputFiles += Get-Item -LiteralPath (Join-Path $projectDirectory 'package.json')
  $inputFiles += Get-Item -LiteralPath (Join-Path $projectDirectory 'pnpm-lock.yaml')
  $inputFiles += Get-Item -LiteralPath (Join-Path $projectDirectory 'vite.config.ts')
  $inputFiles += Get-ChildItem -LiteralPath $projectDirectory -File -Filter '.env*' -ErrorAction SilentlyContinue
  $latestInput = $inputFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  return $latestInput.LastWriteTimeUtc -le $buildTime
}

function Stop-CurrentProductionServer {
  $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $listener) {
    return $true
  }
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
  if (-not $process.CommandLine.Contains($projectDirectory) -or $process.CommandLine -notmatch 'vite\.js.*preview') {
    return $false
  }
  Stop-Process -Id $listener.OwningProcess -Force
  for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
    Start-Sleep -Milliseconds 250
    if (-not (Test-PortInUse)) {
      return $true
    }
  }
  return $false
}

function Open-TasteMap {
  if ($env:FOOD_MAP_SKIP_OPEN -ne '1') {
    Start-Process $appUrl
  }
}

if (Test-TasteMapReady) {
  if (-not $isProduction -or (Test-ProductionBuildCurrent)) {
    Open-TasteMap
    exit 0
  }
  if (-not (Stop-CurrentProductionServer)) {
    Show-LauncherMessage 'The running production service could not be updated safely.'
    exit 1
  }
}

if (Test-PortInUse) {
  Show-LauncherMessage "Port $port is already used by another program. Close it before starting Taste Map."
  exit 1
}

if (-not (Test-Path -LiteralPath $pnpmExecutable) -or -not (Test-Path -LiteralPath $nodeDirectory)) {
  Show-LauncherMessage 'Node.js or pnpm was not found. Install the project runtime first.'
  exit 1
}

$env:Path = "$nodeDirectory;$env:Path"
$env:VITE_APP_ENV = $Environment
if (-not $isProduction) {
  $env:VITE_CLOUD_SYNC_ENABLED = 'true'
}

if (-not (Test-Path -LiteralPath (Join-Path $projectDirectory 'node_modules\vite\package.json'))) {
  $installProcess = Start-Process -FilePath $pnpmExecutable `
    -ArgumentList ($pnpmProjectArguments + @('install', '--frozen-lockfile')) `
    -WorkingDirectory $projectDirectory `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
  if ($installProcess.ExitCode -ne 0) {
    Show-LauncherMessage 'Taste Map dependencies could not be installed.'
    exit 1
  }
}

if ($isProduction) {
  $buildProcess = Start-Process -FilePath $pnpmExecutable `
    -ArgumentList ($pnpmProjectArguments + @('run', 'build')) `
    -WorkingDirectory $projectDirectory `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
  if ($buildProcess.ExitCode -ne 0) {
    Show-LauncherMessage 'Taste Map production build failed.'
    exit 1
  }
  $serverArguments = $pnpmProjectArguments + @('exec', 'vite', 'preview', '--config', 'vite.config.ts', '--host', '127.0.0.1', '--port', "$port", '--strictPort')
}
else {
  # Migrations are incremental and Wrangler only applies files that have not
  # been recorded yet. Run this on every development start so a previously
  # seeded database still receives later schema additions without being reset.
  $migrationProcess = Start-Process -FilePath $pnpmExecutable `
    -ArgumentList ($pnpmProjectArguments + @('run', 'd1:migrate:local')) `
    -WorkingDirectory $projectDirectory `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
  if ($migrationProcess.ExitCode -ne 0) {
    Show-LauncherMessage 'Taste Map test database could not be updated safely.'
    exit 1
  }

  $testDataMarker = Join-Path $projectDirectory '.wrangler\taste-map-test-data.seeded'
  if (-not (Test-Path -LiteralPath $testDataMarker)) {
    $seedProcess = Start-Process -FilePath $pnpmExecutable `
      -ArgumentList ($pnpmProjectArguments + @('run', 'seed:test-users')) `
      -WorkingDirectory $projectDirectory `
      -WindowStyle Hidden `
      -Wait `
      -PassThru
    if ($seedProcess.ExitCode -ne 0) {
      Show-LauncherMessage 'Taste Map test data could not be initialized.'
      exit 1
    }
  }
  $backendPort = 8788
  $backendListener = Get-NetTCPConnection -LocalPort $backendPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $backendListener) {
    Start-Process -FilePath $pnpmExecutable `
      -ArgumentList ($pnpmProjectArguments + @('exec', 'wrangler', 'dev', '--local', '--port', "$backendPort")) `
      -WorkingDirectory $projectDirectory `
      -WindowStyle Hidden
    $backendReady = $false
    for ($attempt = 0; $attempt -lt 60; $attempt += 1) {
      Start-Sleep -Milliseconds 500
      $backendReady = [bool](Get-NetTCPConnection -LocalPort $backendPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
      if ($backendReady) { break }
    }
    if (-not $backendReady) {
      Show-LauncherMessage 'Taste Map test service could not be started.'
      exit 1
    }
  }
  $serverArguments = $pnpmProjectArguments + @('exec', 'vite', '--config', 'vite.config.ts', '--host', '127.0.0.1', '--port', "$port", '--strictPort')
}

Start-Process -FilePath $pnpmExecutable `
  -ArgumentList $serverArguments `
  -WorkingDirectory $projectDirectory `
  -WindowStyle Hidden

$ready = $false
for ($attempt = 0; $attempt -lt 80; $attempt += 1) {
  Start-Sleep -Milliseconds 500
  if (Test-TasteMapReady) {
    $ready = $true
    break
  }
}

if (-not $ready) {
  Show-LauncherMessage "Taste Map did not become ready on port $port."
  exit 1
}

Open-TasteMap
