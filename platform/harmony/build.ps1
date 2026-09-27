param(
  [ValidateSet('debug', 'release')][string]$BuildMode = 'debug',
  [string]$DevEcoHome = $env:DEVECO_HOME,
  [string]$ApiBaseUrl = $env:GUARDIANHUB_API_BASE_URL
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
if (-not $DevEcoHome) {
  $properties = Join-Path $projectRoot 'local.properties'
  if (Test-Path -LiteralPath $properties) {
    $line = Get-Content -LiteralPath $properties | Where-Object { $_ -match '^sdk.dir=' } | Select-Object -First 1
    if ($line) { $DevEcoHome = Split-Path -Parent ($line -replace '^sdk.dir=', '') }
  }
}
$profile = Join-Path $projectRoot 'build-profile.json5'
$localProfile = Join-Path $projectRoot 'build-profile.local.json5'
$config = Join-Path $projectRoot 'entry/src/main/ets/services/ApiConfig.ets'
$oldProfile = [IO.File]::ReadAllBytes($profile)
$oldConfig = [IO.File]::ReadAllBytes($config)
if ($BuildMode -eq 'release') {
  if ($ApiBaseUrl -notmatch '^https://[a-zA-Z0-9.-]+(?::[0-9]+)?/?$') {
    throw 'Release requires GUARDIANHUB_API_BASE_URL with an HTTPS origin.'
  }
  if (-not (Test-Path -LiteralPath $localProfile)) {
    throw 'Release requires an untracked build-profile.local.json5 with rotated signing credentials.'
  }
}
Push-Location $projectRoot
try {
  if ($BuildMode -eq 'release') { Copy-Item -LiteralPath $localProfile -Destination $profile }
  if ($ApiBaseUrl) {
    if ($ApiBaseUrl -notmatch '^https?://[a-zA-Z0-9.-]+(?::[0-9]+)?/?$') { throw 'Invalid API origin.' }
    [IO.File]::WriteAllText($config, "export const API_BASE_URL: string = '$($ApiBaseUrl.TrimEnd('/'))';")
  }
  $cli = Get-Command 'devecocli.cmd' -ErrorAction SilentlyContinue
  if ($cli) {
    & $cli.Source build --product default --modules entry@default --build-mode $BuildMode
  } elseif ($DevEcoHome -and (Test-Path -LiteralPath (Join-Path $DevEcoHome 'tools/hvigor/bin/hvigorw.js'))) {
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
    & (Join-Path $DevEcoHome 'tools/node/node.exe') (Join-Path $DevEcoHome 'tools/hvigor/bin/hvigorw.js') --mode module -p product=default -p module=entry@default -p "buildMode=$BuildMode" assembleHap --no-daemon
  } else { throw 'Install DevEco CLI or set DEVECO_HOME to the DevEco Studio installation.' }
  if ($LASTEXITCODE -ne 0) { throw "Harmony build failed ($LASTEXITCODE)." }
  $hapName = if ($BuildMode -eq 'release') { 'entry-default-signed.hap' } else { 'entry-default-unsigned.hap' }
  $hap = Join-Path $projectRoot "entry/build/default/outputs/default/$hapName"
  if (-not (Test-Path -LiteralPath $hap)) { throw "Expected artifact missing: $hapName" }
  Get-FileHash -LiteralPath $hap -Algorithm SHA256
} finally {
  [IO.File]::WriteAllBytes($profile, $oldProfile)
  [IO.File]::WriteAllBytes($config, $oldConfig)
  Pop-Location
}
