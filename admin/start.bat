@echo off
chcp 65001 >nul
cd /d %~dp0
if not exist ".env" (
    echo [INFO] 创建 .env 配置文件...
    copy .env.example .env
)
echo [INFO] 安装依赖...
call npm install
echo [INFO] 启动 CCTT Web 管理系统...
echo [INFO] 浏览器访问 http://localhost:3456
npm start
pause
