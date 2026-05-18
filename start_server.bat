@echo off
echo ============================================
echo   Multiplayer Test - Server Launcher
echo ============================================
echo.

echo Starting backend services (Docker)...
cd /d "%~dp0"
docker-compose up -d
if errorlevel 1 (
    echo ERROR: Failed to start Docker services. Is Docker running?
    pause
    exit /b 1
)

echo Waiting for backend API to be ready...
:wait_loop
timeout /t 2 /nobreak >nul
curl -s -o nul -w "" http://localhost:5000/health >nul 2>&1
if errorlevel 1 (
    echo   Still waiting for API...
    goto wait_loop
)
echo Backend API is ready!
echo.

echo Starting Godot game server on port 8080...
echo Press Ctrl+C to stop the server.
echo.

REM Use the exported server binary
if exist "%~dp0builds\Server\MultiplayerServer.exe" (
    "%~dp0builds\Server\MultiplayerServer.exe" --headless -- --port 8080
) else (
    echo ERROR: Server binary not found at builds\Server\MultiplayerServer.exe
    echo Please export the Server preset from Godot first.
    pause
    exit /b 1
)

echo.
echo Server stopped.
pause
