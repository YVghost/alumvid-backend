@echo off
cd /d "%~dp0"
if not exist "%~dp0alumvid_admin_desktop\build\windows\x64\runner\Release\alumvid_admin_desktop.exe" (
  echo Primero compila el administrador para Windows siguiendo alumvid_admin_desktop/README.md.
  exit /b 1
)
start "" "%~dp0alumvid_admin_desktop\build\windows\x64\runner\Release\alumvid_admin_desktop.exe"
