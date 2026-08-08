@echo off
REM MindTwin Backend Quick Start Script for Windows

echo.
echo MindTwin Backend Quick Start
echo ============================
echo.

REM Check if Node.js is installed
where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Node.js is not installed. Please install Node.js 20+ first.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('node --version') do set NODE_VERSION=%%i
echo [OK] Node.js version: %NODE_VERSION%
echo.

cd /d "%~dp0"

REM Install dependencies
if not exist "node_modules" (
    echo [INFO] Installing dependencies...
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to install dependencies
        pause
        exit /b 1
    )
)

REM Create .env if it doesn't exist
if not exist ".env" (
    echo [INFO] Creating .env file from .env.example...
    copy .env.example .env >nul
    echo [WARN] Edit backend\.env and set your real JWT_SECRET and API keys.
    echo.
)

REM Run migrations
echo [INFO] Running database migrations...
call npm run migrate
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Migration failed
    pause
    exit /b 1
)

REM Start server
echo.
echo [OK] Setup complete! Starting backend server...
echo [OK] Server: http://localhost:5000
echo [OK] Health check: curl http://localhost:5000/health
echo.

call npm run dev
pause
