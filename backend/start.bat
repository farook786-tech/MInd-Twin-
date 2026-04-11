@echo off
REM MindTwin Backend Quick Start Script for Windows

echo.
echo MindTwin Backend Quick Start
echo ============================
echo.

REM Check if Node.js is installed
where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Node.js is not installed. Please install Node.js 14+ first.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('node --version') do set NODE_VERSION=%%i
echo ✅ Node.js version: %NODE_VERSION%
echo.

REM Navigate to backend directory
if not exist "mindtwin-backend" (
    echo ❌ mindtwin-backend directory not found!
    pause
    exit /b 1
)

cd mindtwin-backend

REM Install dependencies
if not exist "node_modules" (
    echo 📦 Installing dependencies...
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo ❌ Failed to install dependencies
        pause
        exit /b 1
    )
)

REM Create .env if it doesn't exist
if not exist ".env" (
    echo ⚙️  Creating .env file...
    copy .env.example .env
    echo ⚠️  Please edit .env with your configuration
    pause
)

REM Run migrations
echo 🔧 Running database migrations...
call npm run migrate
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Migration failed
    pause
    exit /b 1
)

REM Start server
echo.
echo ✅ Setup complete! Starting backend server...
echo 📍 Server: http://localhost:5000
echo 🏥 Health check: curl http://localhost:5000/health
echo.

call npm run dev
pause
