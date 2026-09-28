param(
  [string]$Hdc = $env:GUARDIANHUB_HDC,
  [string]$RemoteDir = '/data/local/tmp/GuardianHubTests'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gallery = Join-Path $PSScriptRoot 'emulator-gallery'
$zip = Join-Path $PSScriptRoot 'generated/guardianhub-code-risky.zip'
if (-not $Hdc) { $Hdc = 'E:\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe' }
if (-not (Test-Path -LiteralPath $Hdc)) { throw "hdc.exe not found: $Hdc" }
if (-not (Test-Path -LiteralPath $zip)) {
  & (Join-Path $PSScriptRoot 'build-samples.ps1')
}
$files = @(
  '01_privacy_demo.png', '02_privacy_demo_qr.png', '03_form_demo.png',
  'qr-sample-edu.png', 'qr-sample-pay.png', 'qr-sample-short.png',
  'links-risky.txt', 'code-risky.py', 'code-risky.ts',
  'requirement-risky.txt', 'course-paper.txt'
)
& $Hdc shell "mkdir -p $RemoteDir"
if ($LASTEXITCODE -ne 0) { throw "Failed to create remote directory: $RemoteDir" }
foreach ($name in $files) {
  $local = Join-Path $gallery $name
  & $Hdc file send $local "$RemoteDir/$name"
  if ($LASTEXITCODE -ne 0) { throw "Failed to send $name" }
}
& $Hdc file send $zip "$RemoteDir/guardianhub-code-risky.zip"
if ($LASTEXITCODE -ne 0) { throw 'Failed to send guardianhub-code-risky.zip' }
& $Hdc shell "ls $RemoteDir"
if ($LASTEXITCODE -ne 0) { throw 'Remote verification failed' }
Write-Host "Test materials uploaded to $RemoteDir"
Write-Host 'Open this directory in DevEco Device File Browser to export files into the emulator shared files area before using the system share menu.'
