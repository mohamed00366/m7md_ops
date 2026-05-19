@echo off
chcp 65001 > nul
title M7 - Update App Icon

echo.
echo ====================================
echo  Update App Icon + Rebuild APK
echo ====================================
echo.

cd /d "%~dp0"

echo [1/4] Fetching flutter_launcher_icons package...
call flutter pub get
if errorlevel 1 (
    echo ERROR: pub get failed
    pause
    exit /b 1
)

echo.
echo [2/4] Generating launcher icons for all platforms...
call dart run flutter_launcher_icons
if errorlevel 1 (
    echo ERROR: icon generation failed
    pause
    exit /b 1
)

echo.
echo [3/4] Cleaning + building new APK...
call flutter clean
call flutter pub get
call flutter build apk --release
if errorlevel 1 (
    echo ERROR: build failed
    pause
    exit /b 1
)

echo.
echo [4/4] Installing new APK on phone (with new icon)...
call adb uninstall com.m7nexus.m7md_ops
call adb install -r "build\app\outputs\flutter-apk\app-release.apk"

echo.
echo ====================================
echo  DONE! Check your phone:
echo   - App icon should now be M7 Nexus logo
echo ====================================
echo.
pause
