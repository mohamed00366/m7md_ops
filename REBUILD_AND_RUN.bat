@echo off
chcp 65001 > nul
title M7 - Rebuild Flutter App

echo.
echo ====================================
echo  Rebuild + Run Flutter App
echo ====================================
echo.

cd /d "%~dp0"

echo [1/3] Cleaning previous build...
call flutter clean
if errorlevel 1 (
    echo ERROR: flutter clean failed
    pause
    exit /b 1
)

echo.
echo [2/3] Fetching dependencies...
call flutter pub get
if errorlevel 1 (
    echo ERROR: flutter pub get failed
    pause
    exit /b 1
)

echo.
echo [3/3] Running on connected device...
echo.
echo Press 'R' (capital) anytime to hot restart
echo Press 'q' to quit
echo.

call flutter run -d R5CY21B0JGH --debug

pause
