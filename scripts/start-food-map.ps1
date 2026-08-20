$ErrorActionPreference = 'Stop'

$projectDirectory = Split-Path -Parent $PSScriptRoot
$appUrl = 'http://localhost:5173/'
$runtimeDependencies = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies'
$bundledPnpmExecutable = Join-Path $runtimeDependencies 'bin\fallback\pnpm.cmd'
$bundledNodeDirectory = Join-Path $runtimeDependencies 'node\bin'
$pnpmCommand = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
$pnpmExecutable = if ($pnpmCommand) { $pnpmCommand.Source } else { $bundledPnpmExecutable }
$nodeDirectory = if ($nodeCommand) { Split-Path -Parent $nodeCommand.Source } else { $bundledNodeDirectory }

function Test-FoodMapReady {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $appUrl -TimeoutSec 2
    return $response.StatusCode -eq 200 -and $response.Content -match '/src/main.tsx'
  }
  catch {
    return $false
  }
}

function Test-PortInUse {
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $asyncResult = $client.BeginConnect('127.0.0.1', 5173, $null, $null)
    return $asyncResult.AsyncWaitHandle.WaitOne(500) -and $client.Connected
  }
  catch {
    return $false
  }
  finally {
    $client.Dispose()
  }
}

function Show-LauncherMessage([string]$message) {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show($message, 'Food Map', 'OK', 'Information') | Out-Null
}

if (-not (Test-FoodMapReady)) {
  if (Test-PortInUse) {
    Show-LauncherMessage 'Port 5173 is being used by another program. Food Map cannot start.'
    exit 1
  }

  if (-not (Test-Path -LiteralPath $pnpmExecutable)) {
    Show-LauncherMessage 'The local runtime required by Food Map was not found.'
    exit 1
  }

  $env:Path = "$nodeDirectory;$env:Path"
  Start-Process -FilePath $pnpmExecutable `
    -ArgumentList @('run', 'dev', '--', '--host', '127.0.0.1', '--strictPort') `
    -WorkingDirectory $projectDirectory `
    -WindowStyle Hidden

  $ready = $false
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    if (Test-FoodMapReady) {
      $ready = $true
      break
    }
  }

  if (-not $ready) {
    Show-LauncherMessage 'Food Map took too long to start. Please try again.'
    exit 1
  }
}

Start-Process $appUrl
