@echo off
REM Headless unit-test runner. Set GODOT to your Godot 4.5+ binary, or rely on
REM the default install path below.
setlocal
cd /d "%~dp0"

set "GODOT_BIN=%GODOT%"
if "%GODOT_BIN%"=="" set "GODOT_BIN=C:\Program Files\Godot\Godot.exe"

if not exist "%GODOT_BIN%" (
    echo ERROR: Godot executable not found at "%GODOT_BIN%".
    echo Set the GODOT environment variable to your Godot 4.5 binary:
    echo     set "GODOT=C:\path\to\Godot.exe"
    exit /b 1
)

set "LOG=%~dp0test\last_run.log"
REM NOTE: %~dp0 ends with a backslash, which would escape the closing quote in
REM --path "%~dp0" and garble every argument after it (Godot aborts with
REM "Invalid project path" and the stale previous log gets printed). We already
REM cd into the project above, so a plain relative path is correct.
"%GODOT_BIN%" --headless --path . --script res://test/run_tests.gd --log-file "%LOG%"
set EXITCODE=%ERRORLEVEL%

echo.
type "%LOG%"
exit /b %EXITCODE%
