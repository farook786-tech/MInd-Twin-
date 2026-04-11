#!/usr/bin/env pwsh
# MindTwin Startup Script - Starts Backend Automatically

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " MindTwin - Auto Backend Startup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if Node.js is installed
try {
    $nodeVersion = node --version
    Write-Host "[✓] Node.js found: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "[✗] Node.js is not installed or not in PATH" -ForegroundColor Red
    Write-Host "    Please install from https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Check if port 5000 is already in use
$portInUse = Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "[!] Port 5000 is already in use" -ForegroundColor Yellow
    Write-Host "    Backend might be already running" -ForegroundColor Yellow
    Write-Host ""
}

# Start the backend
Write-Host "[INFO] Starting MindTwin Backend..." -ForegroundColor Green
Write-Host "[INFO] Backend will run on http://localhost:5000" -ForegroundColor Green
Write-Host "[INFO] Press Ctrl+C to stop the backend" -ForegroundColor Yellow
Write-Host ""

$backendPath = Join-Path $PSScriptRoot "backend"
Set-Location $backendPath
& node index.js
