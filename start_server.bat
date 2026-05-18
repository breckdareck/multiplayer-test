@echo off
echo ============================================
echo   Multiplayer Test - Server Launcher
echo ============================================
echo.

cd /d "%~dp0"

REM Check if Docker is running
docker info >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker is not running. Please start Docker Desktop first.
    pause
    exit /b 1
)

REM Check if backend containers are already running
docker-compose ps --services --filter "status=running" 2>nul | findstr /r "." >nul 2>&1
if not errorlevel 1 (
    echo Backend services already running.
) else (
    echo Starting backend services...
    docker-compose up -d
    if errorlevel 1 (
        echo ERROR: Failed to start Docker services.
        pause
        exit /b 1
    )
)

REM Check if API is already responding
curl -s -o nul -w "" http://localhost:5000/health >nul 2>&1
if errorlevel 1 (
    echo Waiting for backend API to be ready...
    :wait_loop
    timeout /t 2 /nobreak >nul
    curl -s -o nul -w "" http://localhost:5000/health >nul 2>&1
    if errorlevel 1 (
        echo   Still waiting for API...
        goto wait_loop
    )
)
echo Backend API is ready!
echo.

REM Create logs directory
if not exist "%~dp0logs" mkdir "%~dp0logs"

REM Generate timestamped log filename using PowerShell (wmic removed in Win11)
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set datetime=%%I
set LOG_FILE=%~dp0logs\server_%datetime%.log

echo Starting Godot game server on port 8080...
echo Log file: %LOG_FILE%
echo Press Ctrl+C to stop the server.
echo.

REM Use the exported server binary — check .console.exe first (shows output), then .exe
if exist "%~dp0..\builds\Server\MultiplayerServer.console.exe" (
    "%~dp0..\builds\Server\MultiplayerServer.console.exe" --headless --log-file "%LOG_FILE%" -- --port 8080
) else if exist "%~dp0..\builds\Server\MultiplayerServer.exe" (
    "%~dp0..\builds\Server\MultiplayerServer.exe" --headless --log-file "%LOG_FILE%" -- --port 8080
) else (
    echo ERROR: Server binary not found.
    echo Checked: builds\Server\MultiplayerServer.console.exe
    echo Checked: builds\Server\MultiplayerServer.exe
    echo Please export the Server preset from Godot first.
    pause
    exit /b 1
)

echo.
echo Server stopped.
pause
