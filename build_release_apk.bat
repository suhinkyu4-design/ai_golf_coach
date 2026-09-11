@echo off
chcp 65001 > nul
echo ========================================================
echo [AI Golf Coach] Release APK 빌드를 시작합니다...
echo ========================================================
cd /d "%~dp0"
flutter build apk --release
echo.
echo ========================================================
echo 빌드가 완료되었습니다!
echo 생성된 APK 위치: build\app\outputs\flutter-apk\app-release.apk
echo ========================================================
pause
