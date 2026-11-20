@echo off
chcp 65001 >nul
echo 正在关掉小鲸鱼…
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -and ($_.CommandLine -match 'server\.ps1' -or $_.CommandLine -match 'shell\.ps1') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo 已停止。
timeout /t 2 /nobreak >nul
