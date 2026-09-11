@echo off
chcp 65001 > nul
echo ========================================================
echo [AI Golf Coach] Git 백그라운드 자동 푸시 서비스를 시작합니다.
echo ========================================================
powershell -ExecutionPolicy Bypass -File "%~dp0auto_git_push.ps1"
pause
