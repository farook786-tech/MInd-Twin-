$ErrorActionPreference = 'Stop'

$taskName = 'MindTwinBackendAutostart'
$backendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $backendDir 'run_persistent.bat'

if (-not (Test-Path $runner)) {
  throw "Cannot find $runner"
}

$escapedRunner = '"' + $runner + '"'
$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c $escapedRunner"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Starts MindTwin backend with PM2 at user logon' | Out-Null

Write-Host "Created scheduled task: $taskName"
Write-Host 'It will run at every Windows logon and start backend with PM2.'
Write-Host 'Run this once after creating the task:'
Write-Host '  npm run save:pm2'
