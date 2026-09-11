@echo off
chcp 65001 > nul
echo ========================================================
echo [AI Golf Coach] Play 스토어 업로드용 App Bundle (AAB) 빌드를 시작합니다...
echo ========================================================
cd /d "%~dp0"
flutter build appbundle --release
echo.
echo ========================================================
echo 빌드가 완료되었습니다!
echo 생성된 AAB 위치: build\app\outputs\bundle\release\app-release.aab
echo ========================================================
pause
