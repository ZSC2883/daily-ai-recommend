@echo off
chcp 65001 >nul
setlocal
set DIR=%~dp0

echo ============================================
echo   每日 AI 推荐 - 一键部署
echo ============================================
echo.

echo [1/4] 检测环境...
where claude >nul 2>&1
if errorlevel 1 (
  echo   [错误] 未找到 claude CLI
  echo   请先安装 Claude Code 并登录：npm install -g @anthropic-ai/claude-code
  pause
  exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
  echo   [错误] 未找到 Node.js，请先安装
  pause
  exit /b 1
)
echo   [OK] claude 与 node 均已就绪

echo [2/4] 创建计划任务...
schtasks /Create /SC DAILY /ST 08:40 /TN "DailyAIRecommend" /TR "wscript.exe \"%DIR%launcher.vbs\"" /IT /F >nul 2>&1
schtasks /Create /SC ONLOGON /TN "DailyAIRecommendServer" /TR "wscript.exe \"%DIR%server-launcher.vbs\"" /IT /F >nul 2>&1
echo   [OK] 已创建「每日推荐」和「登录自启」两个任务

echo [3/4] 启动本地服务...
wscript.exe "%DIR%server-launcher.vbs"
timeout /t 2 /nobreak >nul
echo   [OK] 服务已启动: http://127.0.0.1:8765/

echo [4/4] 首次生成推荐（约 1-2 分钟，请稍候）...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DIR%daily-ai-recommend.ps1" -Test

echo.
echo ============================================
echo   部署完成！
echo   - 每天 08:40 自动弹窗推荐
echo   - 页面地址: http://127.0.0.1:8765/
echo   - 收藏文件: %DIR%收藏.md
echo ============================================
pause
