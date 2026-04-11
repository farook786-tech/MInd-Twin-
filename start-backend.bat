@echo off
REM MindTwin Startup Script - Starts Backend Automatically

echo.
echo ========================================
echo  MindTwin - Auto Backend Startup
echo ========================================
echo.

REM Check if Node.js is installed
node --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js is not installed or not in PATH
    echo         Please install Node.js from https://nodejs.org/
    pause
    exit /b 1
)

echo [INFO] Node.js found: 
node --version
echo.

REM Check if port 5000 is already in use
netstat -ano | findstr :5000 >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Port 5000 is already in use
    echo [INFO] Backend might be already running
    echo.
)

REM Start the backend
echo [INFO] Starting MindTwin Backend...
echo [INFO] Backend will run on http://localhost:5000
echo.
echo [INFO] Press Ctrl+C in this window to stop the backend
echo.

cd /d "%~dp0backend"
node index.js

pause
