# Starts GuardianHub on ports that do not collide with HekGemi (8000/5173).
param(
    [int]$ApiPort = 8001,
    [int]$WebPort = 5174,
    [string]$HostAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Platform = Join-Path $Root "platform"
$Backend = Join-Path $Platform "backend"
$Frontend = Join-Path $Platform "frontend"

if (-not (Test-Path (Join-Path $Backend "main.py"))) {
    throw "Cannot find platform/backend/main.py under $Root"
}

function Test-PortListen([int]$Port) {
    return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-HttpOk([string]$Url, [int]$Seconds = 45) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { return $true }
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    return $false
}

$apiUrl = "http://${HostAddress}:$ApiPort"
$webUrl = "http://${HostAddress}:$WebPort"

if (-not (Test-PortListen $ApiPort)) {
    $env:GUARDIANHUB_CORS_ORIGINS = "$webUrl,http://localhost:$WebPort"
    Start-Process -FilePath "python" `
        -ArgumentList @("-m", "uvicorn", "main:app", "--host", $HostAddress, "--port", "$ApiPort", "--lifespan", "off") `
        -WorkingDirectory $Backend `
        -WindowStyle Hidden | Out-Null
    Write-Host "Started API on $ApiPort"
} else {
    Write-Host "API already listening on $ApiPort"
}

if (-not (Wait-HttpOk "$apiUrl/api/health" 45)) {
    throw "API failed to become healthy at $apiUrl/api/health"
}

if (-not (Test-PortListen $WebPort)) {
    $env:VITE_API_BASE_URL = $apiUrl
    Start-Process -FilePath "npm.cmd" `
        -ArgumentList @("run", "dev", "--", "--host", $HostAddress, "--port", "$WebPort", "--strictPort") `
        -WorkingDirectory $Frontend `
        -WindowStyle Hidden | Out-Null
    Write-Host "Started web on $WebPort"
} else {
    Write-Host "Web already listening on $WebPort"
}

if (-not (Wait-HttpOk $webUrl 60)) {
    throw "Frontend failed to become healthy at $webUrl"
}

Write-Host "OK"
Write-Host "API  $apiUrl/api/health"
Write-Host "WEB  $webUrl"
