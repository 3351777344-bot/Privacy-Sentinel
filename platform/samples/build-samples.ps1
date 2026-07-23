$ErrorActionPreference = 'Stop'

$sampleRoot = $PSScriptRoot
$sourceDirectory = Join-Path $sampleRoot 'code-risky'
$outputDirectory = Join-Path $sampleRoot 'generated'
$outputArchive = Join-Path $outputDirectory 'guardianhub-code-risky.zip'

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
if (Test-Path -LiteralPath $outputArchive -PathType Leaf) {
  Remove-Item -LiteralPath $outputArchive -Force
}

Compress-Archive -Path $sourceDirectory `
  -DestinationPath $outputArchive `
  -CompressionLevel Optimal

Write-Host "Generated: $outputArchive"
