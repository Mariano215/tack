@echo off
REM PowerShell and cmd.exe cannot run the extensionless `docmd` shebang script.
py "%~dp0docmd" %*
