@echo off
chcp 65001 >nul
title Activation Codes - Dental Clinic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0activation-codes.ps1"
echo.
pause
