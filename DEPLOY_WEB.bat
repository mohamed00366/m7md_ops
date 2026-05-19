@echo off
chcp 65001 > nul
title M7 - Deploy Web to Firebase Hosting

echo.
echo ============================================
echo  🌐 Deploy Web to Firebase Hosting
echo ============================================
echo.
echo Output URL: https://m7-nexus.web.app
echo Also available at: https://m7-nexus.firebaseapp.com
echo.

cd /d "%~dp0"

echo [1/4] flutter clean...
call flutter clean
if errorlevel 1 goto :error

echo.
echo [2/4] flutter pub get...
call flutter pub get
if errorlevel 1 goto :error

echo.
echo [3/4] flutter build web --release...
call flutter build web --release
if errorlevel 1 goto :error

echo.
echo [4/4] firebase deploy --only hosting...
call firebase deploy --only hosting
if errorlevel 1 goto :error

echo.
echo ============================================
echo  ✅ DONE — Open these URLs on iPhone/iPad:
echo     https://m7-nexus.web.app
echo     https://m7-nexus.firebaseapp.com
echo.
echo  📱 To install as an app on iOS:
echo     1. Open the URL in Safari (not Chrome!)
echo     2. Tap the Share button (square + up arrow)
echo     3. Tap "Add to Home Screen"
echo     4. The app icon appears on your home screen.
echo ============================================
echo.
pause
exit /b 0

:error
echo.
echo ❌ Deploy failed — see error above.
echo.
echo If you've never used Firebase CLI before, run ONCE:
echo    npm install -g firebase-tools
echo    firebase login
echo.
pause
exit /b 1
