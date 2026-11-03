@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1"
set "install_status=%errorlevel%"
if not "%install_status%"=="0" (echo 安装失败，请查看上方错误。) else (echo 安装检查完成。)
pause
exit /b %install_status%
