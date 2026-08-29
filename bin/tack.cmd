@echo off
setlocal
set "TACK_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%TACK_BASH%" set "TACK_BASH="
for /f "delims=" %%G in ('where.exe git.exe 2^>nul') do if not defined TACK_BASH call :find_git_bash "%%~dpG"
if not defined TACK_BASH (
  echo tack: Git Bash was not found. Install Git for Windows, or add its git.exe to PATH.
  exit /b 1
)
set "TACK_DIR=%~dp0"
set "TACK_DIR=%TACK_DIR:\=/%"
"%TACK_BASH%" "%TACK_DIR%tack" %*
exit /b %ERRORLEVEL%

:find_git_bash
for %%D in ("%~1..") do if exist "%%~fD\bin\bash.exe" set "TACK_BASH=%%~fD\bin\bash.exe"
exit /b
