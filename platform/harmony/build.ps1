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
  if ($ApiBaseUrl -notmatch '^https://[a-zA-Z0-9.-]+(?::[0-9]+)?/?$' -or
      $ApiBaseUrl.TrimEnd('/') -ne 'https://api.guardianhub.tech') {
    throw 'Release requires ApiBaseUrl=https://api.guardianhub.tech.'
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
  # hvigor produces an unsigned HAP. Signing is a separate explicit step so
  # credentials never enter the tracked project configuration.
  $hapName = 'entry-default-unsigned.hap'
  $hap = Join-Path $projectRoot "entry/build/default/outputs/default/$hapName"
  if (-not (Test-Path -LiteralPath $hap)) { throw "Expected artifact missing: $hapName" }
  $bytes = [IO.File]::ReadAllBytes($hap)
  if ($BuildMode -eq 'release') {
    $zip = [IO.Compression.ZipFile]::OpenRead($hap)
    try {
      $text = New-Object Text.StringBuilder
      foreach ($entry in $zip.Entries) {
        $stream = $entry.Open()
        try {
          $buffer = New-Object IO.MemoryStream
          $stream.CopyTo($buffer)
          [void]$text.Append([Text.Encoding]::UTF8.GetString($buffer.ToArray()))
        } finally {
          $stream.Dispose()
        }
      }
      $payload = $text.ToString()
    } finally {
      $zip.Dispose()
    }
    if ($payload -notmatch 'https://api\.guardianhub\.tech') {
      throw 'Release HAP does not contain https://api.guardianhub.tech.'
    }
    foreach ($forbidden in @('10.0.2.2:8001', '127.0.0.1', 'localhost')) {
      if ($payload -match [regex]::Escape($forbidden)) {
        throw "Release HAP contains forbidden development address: $forbidden"
      }
    }
  }
  $hash = (Get-FileHash -LiteralPath $hap -Algorithm SHA256).Hash
  Write-Host "HAP: $hap"
  Write-Host "Size: $($bytes.Length) bytes"
  Write-Host "SHA-256: $hash"
} finally {
  [IO.File]::WriteAllBytes($profile, $oldProfile)
  [IO.File]::WriteAllBytes($config, $oldConfig)
  Pop-Location
}
