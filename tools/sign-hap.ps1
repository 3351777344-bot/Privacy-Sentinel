param(
  [string]$DevEcoHome = $(if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'E:\DevEcoStudio' }),
  [Parameter(Mandatory = $true)][string]$StoreFile,
  [Parameter(Mandatory = $true)][string]$StorePassword,
  [string]$KeyAlias = 'guardianhub',
  [string]$KeyPassword = '',
  [Parameter(Mandatory = $true)][string]$ProfileFile,
  [Parameter(Mandatory = $true)][string]$CertFile,
  [Parameter(Mandatory = $true)][string]$InFile,
  [string]$OutFile = '',
  [string]$SignAlg = 'SHA256withECDSA',
  [int]$CompatibleVersion = 22
)

# Sign an already-built HAP with the SDK's hap-sign-tool.
#
# Why this exists: DevEco's build-profile expects the *encrypted* password string
# (>= 32 chars) that its IDE writes, which a plaintext password in a local config
# cannot satisfy. This script signs the packaged HAP directly instead, so the
# plaintext keystore password never has to be stored in the project.

$ErrorActionPreference = 'Stop'

$java = Join-Path $DevEcoHome 'jbr/bin/java.exe'
if (-not (Test-Path -LiteralPath $java)) {
  throw "Java not found at $java. Set -DevEcoHome to the DevEco Studio install directory."
}

$signTool = Get-ChildItem -Path (Join-Path $DevEcoHome 'sdk') -Recurse -Filter 'hap-sign-tool.jar' -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $signTool) {
  throw "hap-sign-tool.jar not found under $DevEcoHome\sdk."
}

foreach ($required in @{ '-StoreFile' = $StoreFile; '-ProfileFile' = $ProfileFile; '-CertFile' = $CertFile; '-InFile' = $InFile }.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $required.Value)) {
    throw "$($required.Key) not found: $($required.Value)"
  }
}

if (-not $OutFile) {
  $directory = Split-Path -Parent $InFile
  $OutFile = Join-Path $directory ((Split-Path -Leaf $InFile) -replace '-unsigned', '-signed')
}
if (-not $KeyPassword) { $KeyPassword = $StorePassword }

Write-Host "Signing $(Split-Path -Leaf $InFile) -> $(Split-Path -Leaf $OutFile)"
& $java -jar $signTool sign-app `
  -mode localSign `
  -keyAlias $KeyAlias `
  -keyPwd $KeyPassword `
  -appCertFile $CertFile `
  -profileFile $ProfileFile `
  -inFile $InFile `
  -signAlg $SignAlg `
  -keystoreFile $StoreFile `
  -keystorePwd $StorePassword `
  -outFile $OutFile `
  -compatibleVersion $CompatibleVersion
if ($LASTEXITCODE -ne 0) {
  throw "hap-sign-tool failed ($LASTEXITCODE)."
}

$hash = Get-FileHash -LiteralPath $OutFile -Algorithm SHA256
$size = (Get-Item -LiteralPath $OutFile).Length
Write-Host ''
Write-Host "Signed HAP : $OutFile"
Write-Host "Size       : $size bytes"
Write-Host "SHA-256    : $($hash.Hash)"
