Set-Location $PSScriptRoot

Write-Host 'Checking PM2 process list...' -ForegroundColor Cyan
npx pm2 list

Write-Host ''
Write-Host 'Health check (http://localhost:5000/health)...' -ForegroundColor Cyan
try {
  $res = Invoke-RestMethod -Uri 'http://localhost:5000/health' -TimeoutSec 5
  $res | ConvertTo-Json -Depth 4
} catch {
  Write-Host 'Health check failed. Backend may not be running yet.' -ForegroundColor Yellow
}
