@echo off
chcp 65001 > nul
title M7 - Build + Install APK

echo.
echo ====================================
echo  Build Release APK + Install on Phone
echo ====================================
echo.

cd /d "%~dp0"

echo [1/4] Cleaning previous build...
call flutter clean
if errorlevel 1 (
    echo ERROR: flutter clean failed
    pause
    exit /b 1
)

echo.
echo [2/4] Fetching dependencies...
call flutter pub get
if errorlevel 1 (
    echo ERROR: flutter pub get failed
    pause
    exit /b 1
)

echo.
echo [3/4] Building release APK (5-10 minutes)...
call flutter build apk --release
if errorlevel 1 (
    echo ERROR: build failed
    pause
    exit /b 1
)

echo.
echo [4/4] Uninstalling old + installing new APK on phone...
call adb uninstall com.m7nexus.m7md_ops
call adb install -r "build\app\outputs\flutter-apk\app-release.apk"

echo.
echo ====================================
echo  DONE!
echo ====================================
echo.
echo Now on your phone:
echo  1. Open the app
echo  2. Login with AE-V-0001
echo  3. Press Allow on notification request
echo  4. Press Home (put app in background)
echo.
echo Then run the test SQL in Supabase Dashboard.
echo.
pause
