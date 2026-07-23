param(
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$npmCache = Join-Path $projectRoot '.cache\npm'
New-Item -ItemType Directory -Force -Path $npmCache | Out-Null

# DevEco Studio bundles its own Node.js. Isolating npm's cache here avoids
# depending on a machine-wide npm cache path or its permissions.
$env:NPM_CONFIG_CACHE = $npmCache
$env:npm_config_cache = $npmCache

$cliCommand = Get-Command 'devecocli.cmd' -ErrorAction SilentlyContinue
if ($null -ne $cliCommand) {
  $cliPath = $cliCommand.Source
} else {
  $cliPath = Join-Path $env:LOCALAPPDATA 'Programs\deveco-cli\devecocli.cmd'
}

if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
  throw 'DevEco CLI was not found. Install it or add devecocli.cmd to PATH.'
}

Push-Location $projectRoot
try {
  & $cliPath build `
    --product default `
    --modules entry@default `
    --build-mode $BuildMode
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
