@echo off
REM ===========================================================
REM  GameBoost launcher - runs the PowerShell app as Admin
REM ===========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0GameBoost.ps1\"' -Verb RunAs"
