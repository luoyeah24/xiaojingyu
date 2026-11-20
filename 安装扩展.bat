@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

set "EXT=%~dp0extension"

echo ============================================================
echo   小鲸鱼扩展 - 安装助手
echo ============================================================
echo.

if not exist "%EXT%\manifest.json" (
    echo [错误] 找不到 "%EXT%\manifest.json"
    echo        说明这个压缩包解压不完整，请重新解压。
    echo.
    pause
    exit /b 1
)

echo 检查通过，扩展文件在：
echo   %EXT%
echo.
echo 里面应该有这两个文件：
dir /b "%EXT%"
echo.

echo ------------------------------------------------------------
echo  接下来这一步很关键，请严格按顺序：
echo ------------------------------------------------------------
echo  1. 浏览器会打开 edge://extensions
echo  2. 打开左下角「开发人员模式」开关
echo  3. 点「加载解压缩的扩展」
echo  4. 在弹出的窗口里，进到下面这个路径，选「extension」文件夹：
echo.
echo     %EXT%
echo.
echo  ！！注意：要选 extension 这个文件夹本身，
echo      不是它的上一层，也不是 zip 文件。
echo ------------------------------------------------------------
echo.

start "" explorer "%EXT%"
timeout /t 2 /nobreak >nul
start "" msedge.exe "edge://extensions"
timeout /t 3 /nobreak >nul

echo 装好之后，列表里会出现「小鲸鱼 · 后台」。
echo 如果它旁边有红色「错误」按钮，点开把文字发给我。
echo.
pause
