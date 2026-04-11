@echo off
setlocal

echo MindTwin backend persistent startup
echo ----------------------------------

cd /d "%~dp0"

if not exist ".env" (
  copy ".env.example" ".env" >nul
)

if not exist "node_modules" (
  echo Installing dependencies...
  call npm install
  if %ERRORLEVEL% NEQ 0 (
    echo Dependency install failed.
    exit /b 1
  )
)

call npm run start:pm2
if %ERRORLEVEL% NEQ 0 (
  echo PM2 start failed.
  exit /b 1
)

call npm run save:pm2
echo Backend is running in background with PM2.
echo Health: http://localhost:5000/health

endlocal
