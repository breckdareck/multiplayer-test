@echo off
echo ============================================
echo   Multiplayer Test - Server Shutdown
echo ============================================
echo.

echo Stopping backend services...
cd /d "%~dp0"
docker-compose down
if errorlevel 1 (
    echo WARNING: docker-compose down had issues.
) else (
    echo Backend services stopped.
)

echo.
echo Done.
pause
