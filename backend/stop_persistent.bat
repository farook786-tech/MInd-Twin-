@echo off
setlocal

echo Stopping MindTwin backend persistent process
echo -------------------------------------------

cd /d "%~dp0"
call npm run stop:pm2

echo Done.
endlocal
