@echo off
:: Check for admin privileges and self-elevate if needed
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:menu
cls
echo ==========================================================
echo                  aka_techno
echo ==========================================================
echo  Follow my YouTube channel: https://www.youtube.com/@aka_techno
echo  By : Behnam Tajadini
echo ==========================================================
echo.
echo DNS Configuration Tool
echo ====================
echo 1. Set Custom DNS Servers
echo 2. Verify DNS Settings
echo 3. Restore Default Settings
echo 4. Test DNS Servers with URL
echo 5. Open DNS Configuration GUI
echo 6. Exit
echo.

set /p choice="Enter your choice (1-6): "

if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%~dp0set-dns-servers.ps1"
    pause
    goto menu
)
if "%choice%"=="2" (
    powershell -ExecutionPolicy Bypass -File "%~dp0verify-dns.ps1"
    pause
    goto menu
)
if "%choice%"=="3" (
    powershell -ExecutionPolicy Bypass -File "%~dp0restore-dns-settings.ps1"
    pause
    goto menu
)
if "%choice%"=="4" (
    powershell -ExecutionPolicy Bypass -File "%~dp0test-dns-servers.ps1"
    pause
    goto menu
)
if "%choice%"=="5" (
    powershell -ExecutionPolicy Bypass -File "%~dp0start-dns-gui.ps1"
    goto menu
)
if "%choice%"=="6" (
    exit
)

goto menu
