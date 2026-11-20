@echo off
chcp 65001 >nul
cd /d "%~dp0"

rem 关掉已经在跑的服务
tasklist /FI "WINDOWTITLE eq 小鲸鱼服务*" >nul 2>&1

rem 启动本地服务（隐藏窗口）
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0server.ps1"

rem 等端口就绪
timeout /t 2 /nobreak >nul

rem 启动桌面壳
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0shell.ps1"
