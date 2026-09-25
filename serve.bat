@echo off
rem Live-sync Spike Rush into Roblox Studio.
rem   1. Double-click this file (it starts "rojo serve" on localhost:34872).
rem   2. In Studio, open a place (or SpikeRush.rbxlx), open the Rojo plugin and press Connect.
rem The Studio plugin must be Rojo 7.7.x; "rojo plugin install" installs the matching one.
cd /d "%~dp0"
where rojo >nul 2>nul
if errorlevel 1 (
	echo rojo not found. Install the toolchain first: "rokit install" or "aftman install".
	pause
	exit /b 1
)
rojo --version
rojo serve default.project.json %*
pause
