param(
  [string]$BaseUrl = 'http://127.0.0.1:8000'
)

$ErrorActionPreference = 'Stop'

function Invoke-CurlJson {
  param(
    [string[]]$Arguments,
    [string]$FailureMessage
  )

  $json = & curl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw $FailureMessage
  }
  return $json | ConvertFrom-Json
}

& (Join-Path $PSScriptRoot 'build-samples.ps1')

$privacyImage = Join-Path $PSScriptRoot '..\backend\static\samples\privacy_sentinel_demo_qr.png'
$codeArchive = Join-Path $PSScriptRoot 'generated\guardianhub-code-risky.zip'
$document = Join-Path $PSScriptRoot 'doc-risky\course-paper.txt'
$requirementFile = Join-Path $PSScriptRoot 'doc-risky\requirement.txt'
$requirementText = Get-Content -Raw -Encoding UTF8 -LiteralPath $requirementFile

$health = Invoke-RestMethod -Uri "$BaseUrl/api/health" -Method Get

$privacyArguments = @(
  '-sS', '-X', 'POST', "$BaseUrl/api/detect",
  '-F', 'processing_mode=local',
  '-F', "file=@$privacyImage;type=image/png"
)
$privacy = Invoke-CurlJson `
  -FailureMessage 'Privacy Sentinel request failed.' `
  -Arguments $privacyArguments
$processBody = @{
  imageId = $privacy.imageId
  scope = 'all'
  maskType = 'mosaic'
  itemIds = @()
} | ConvertTo-Json
$processed = Invoke-RestMethod `
  -Uri "$BaseUrl/api/privacy/process" `
  -Method Post `
  -ContentType 'application/json' `
  -Body $processBody

$codeArguments = @(
  '-sS', '-X', 'POST', "$BaseUrl/api/code/analyze",
  '-F', 'processing_mode=local',
  '-F', "file=@$codeArchive;type=application/zip"
)
$code = Invoke-CurlJson `
  -FailureMessage 'Code Guardian request failed.' `
  -Arguments $codeArguments

$linkBody = @{
  url = 'http://xn--campus-login.example/login?redirect=payment&token=demo123456789'
  source = 'sms'
} | ConvertTo-Json
$link = Invoke-RestMethod `
  -Uri "$BaseUrl/api/link/check" `
  -Method Post `
  -ContentType 'application/json; charset=utf-8' `
  -Body ([Text.Encoding]::UTF8.GetBytes($linkBody))

$docArguments = @(
  '-sS', '-X', 'POST', "$BaseUrl/api/doc/check",
  '--form-string',
  "requirement_text=$requirementText",
  '-F',
  "files=@$document;type=text/plain"
)
$doc = Invoke-CurlJson `
  -FailureMessage 'Doc Shield request failed.' `
  -Arguments $docArguments

@(
  [pscustomobject]@{
    Module = 'health'
    Result = $health.status
    Score = '-'
    Details = $health.message
  }
  [pscustomobject]@{
    Module = 'privacy'
    Result = $privacy.riskLevel
    Score = $privacy.score
    Details = "items=$($privacy.items.Count)"
  }
  [pscustomobject]@{
    Module = 'privacy-process'
    Result = 'ok'
    Score = '-'
    Details = $processed.processedImageUrl
  }
  [pscustomobject]@{
    Module = 'code'
    Result = $code.riskLevel
    Score = $code.score
    Details = "files=$($code.scannedFiles), findings=$($code.vulnerabilities.Count)"
  }
  [pscustomobject]@{
    Module = 'link'
    Result = $link.riskLevel
    Score = $link.score
    Details = "checks=$($link.checks.Count), shouldOpen=$($link.shouldOpen)"
  }
  [pscustomobject]@{
    Module = 'doc'
    Result = $doc.riskLevel
    Score = $doc.score
    Details = "checks=$($doc.checks.Count)"
  }
) | Format-Table -AutoSize
