@echo off
chcp 65001 >nul
echo [1/4] flutter doctor
call flutter doctor
echo [2/4] flutter pub get
call flutter pub get || goto :err
echo [3/4] flutter build apk (arm64 + armv7 + x86_64)
call flutter build apk --release --split-per-abi || goto :err
echo [4/4] Done. APK files:
dir /b build\app\outputs\flutter-apk\*.apk
echo.
echo For most phones use: app-arm64-v8a-release.apk
echo Install via USB:  adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
pause
exit /b 0
:err
echo Build failed. Check the messages above.
pause
exit /b 1
