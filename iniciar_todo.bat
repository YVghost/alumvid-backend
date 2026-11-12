@echo off
cd /d "%~dp0"
docker compose -f compose.yaml up -d
if errorlevel 1 exit /b 1
start "" "%~dp0iniciar_admin_desktop.bat"
start "" "%~dp0iniciar_app_movil.bat"
