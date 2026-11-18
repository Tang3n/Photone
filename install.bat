@echo off
rem Photone for Windows: download, build, install, clean up. Nothing needs to be installed first.
rem
rem   In Command Prompt (the README has this line):
rem     curl -L -o "%TEMP%\photone-install.bat" https://raw.githubusercontent.com/TominoCZ/Photone/main/install.bat && "%TEMP%\photone-install.bat"
rem
rem   install.bat              install, or bring an installed Photone up to date
rem   install.bat /uninstall   take it away again (photos, the catalog and settings stay)
rem
rem What it does: fetches the source and a build tool (uv, which brings its own Python) into a
rem temporary folder, runs scripts\build_windows.py there, copies the result to
rem "C:\Program Files\Photone", makes the shortcuts and the entry in "Installed apps", and
rem deletes the temporary folder. Windows asks once for permission (Program Files needs it).
setlocal EnableExtensions EnableDelayedExpansion
title Photone Setup

set "SOURCE=https://github.com/TominoCZ/Photone/archive/refs/heads/main.zip"
set "UV=https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip"
set "PHOTONE_DEST=%ProgramFiles%\Photone"
rem (Asked from a 32-bit program, Windows answers "Program Files (x86)": the real one, then.)
if defined ProgramW6432 set "PHOTONE_DEST=%ProgramW6432%\Photone"
set "DESKTOP=%PUBLIC%\Desktop\Photone.lnk"
set "MENU=%ProgramData%\Microsoft\Windows\Start Menu\Programs\Photone.lnk"
set "KEY=HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\Photone"
set "LOG=%TEMP%\photone-install.log"
set "PHOTONE_SELF=%~f0"
set "WORK=%TEMP%\photone-%RANDOM%"

rem The whole window in one color, by how things stand: green while all is well, red when
rem setup stops. (`color`, which every Windows has: escape codes for single words came out as
rem "[92m" in consoles that do not know them.)
color 0A

set "MODE=install" & set "ELEVATED=" & set "PASS=/elevated"
for %%a in (%*) do (
    if /I "%%~a"=="/uninstall" set "MODE=uninstall" & set "PASS=/elevated /uninstall"
    if /I "%%~a"=="/elevated" set "ELEVATED=1"
)

rem Program Files and the shortcuts for everyone need an administrator: ask once, and carry
rem on in the window Windows opens. (/elevated: that window is this file again, told not to ask
rem a second time, whatever the check below would say there.)
if not defined ELEVATED net session >nul 2>&1 || goto :elevate
if "%MODE%"=="uninstall" goto :uninstall

set "STEPS=7" & set "STEP=0"
echo.
echo   ============================================================
echo    PHOTONE SETUP
echo    A raw photo editor built around a color wheel
echo   ============================================================
echo.
echo    Installs to: %PHOTONE_DEST%
echo. > "%LOG%"

rem ---- 1 ------------------------------------------------------------------------------------
call :step "Checking this computer"
if /I not "%PROCESSOR_ARCHITECTURE%"=="AMD64" if /I not "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    set "WHY=Photone needs 64-bit Windows." & goto :failed
)
where curl >nul 2>&1 || (set "WHY=Photone needs Windows 10 (version 1803) or later." & goto :failed)
where tar >nul 2>&1 || (set "WHY=Photone needs Windows 10 (version 1803) or later." & goto :failed)
:closed
tasklist /FI "IMAGENAME eq Photone.exe" 2>nul | find /I "Photone.exe" >nul
if not errorlevel 1 (
    echo         Photone is running. Close it, then press a key.
    pause >nul
    goto :closed
)
mkdir "%WORK%" >nul 2>&1 || (set "WHY=The temporary folder could not be made: %WORK%" & goto :failed)
call :done "64-bit Windows, ready"

rem ---- 2 ------------------------------------------------------------------------------------
call :step "Downloading Photone"
curl -fL --progress-bar -o "%WORK%\source.zip" "%SOURCE%"
if errorlevel 1 (set "WHY=The download failed. Is this computer online?" & goto :failed)
tar -xf "%WORK%\source.zip" -C "%WORK%" >> "%LOG%" 2>&1
if errorlevel 1 (set "WHY=The download could not be unpacked." & goto :failed)
rem (The folder in GitHub's archive of a branch: the repository's name and the branch's.)
set "TREE=%WORK%\Photone-main"
if not exist "%TREE%\scripts\build_windows.py" (set "WHY=The download is not what was expected." & goto :failed)
call :done "Source code"

rem ---- 3 ------------------------------------------------------------------------------------
call :step "Getting the build tool"
curl -fL --progress-bar -o "%WORK%\uv.zip" "%UV%"
if errorlevel 1 (set "WHY=The build tool could not be downloaded." & goto :failed)
tar -xf "%WORK%\uv.zip" -C "%WORK%" >> "%LOG%" 2>&1
if not exist "%WORK%\uv.exe" (set "WHY=The build tool could not be unpacked." & goto :failed)
rem (All of it stays in the temporary folder: nothing of Python is installed on this computer.)
set "PATH=%WORK%;%PATH%"
set "UV_CACHE_DIR=%WORK%\uv-cache"
set "UV_PYTHON_INSTALL_DIR=%WORK%\uv-python"
set "UV_NO_PROGRESS=1"
call :done "uv (temporary: removed again at the end)"

rem ---- 4 ------------------------------------------------------------------------------------
call :step "Building Photone"
echo         Python, Qt and the raw decoder are downloaded: about 150 MB.
echo         This takes a few minutes. Nothing is stuck.
uv run --no-project --python 3.13 python "%TREE%\scripts\build_windows.py" >> "%LOG%" 2>&1
if errorlevel 1 (set "WHY=The build failed." & goto :failed)
if not exist "%TREE%\bin\Photone.exe" (set "WHY=The build made no Photone.exe." & goto :failed)
call :done "Built"

rem ---- 5 ------------------------------------------------------------------------------------
call :step "Installing"
robocopy "%TREE%\bin" "%PHOTONE_DEST%" /MIR /NFL /NDL /NJH /NJS /NP >> "%LOG%" 2>&1
if errorlevel 8 (set "WHY=The files could not be copied to %PHOTONE_DEST%." & goto :failed)
copy /Y "%~f0" "%PHOTONE_DEST%\uninstall.bat" >nul 2>&1
rem Python's compiled files, made now: Program Files cannot be written to later, and without
rem them every start would compile the program again.
"%PHOTONE_DEST%\python\python.exe" -m compileall -q "%PHOTONE_DEST%\photone" "%PHOTONE_DEST%\lib" >> "%LOG%" 2>&1
call :done "%PHOTONE_DEST%"

rem ---- 6 ------------------------------------------------------------------------------------
call :step "Adding shortcuts"
powershell -NoProfile -Command "$w = New-Object -ComObject WScript.Shell; foreach ($at in $env:DESKTOP, $env:MENU) { $s = $w.CreateShortcut($at); $s.TargetPath = $env:PHOTONE_DEST + '\Photone.exe'; $s.WorkingDirectory = $env:PHOTONE_DEST; $s.Description = 'Photone, a raw photo editor'; $s.Save() }" >> "%LOG%" 2>&1
if errorlevel 1 (set "WHY=The shortcuts could not be made." & goto :failed)
reg add "%KEY%" /v DisplayName /d "Photone" /f >nul
reg add "%KEY%" /v DisplayIcon /d "%PHOTONE_DEST%\Photone.exe" /f >nul
reg add "%KEY%" /v InstallLocation /d "%PHOTONE_DEST%" /f >nul
reg add "%KEY%" /v UninstallString /d "\"%PHOTONE_DEST%\uninstall.bat\" /uninstall" /f >nul
reg add "%KEY%" /v NoModify /t REG_DWORD /d 1 /f >nul
reg add "%KEY%" /v NoRepair /t REG_DWORD /d 1 /f >nul
call :done "Desktop, Start menu, and Installed apps (to uninstall)"

rem ---- 7 ------------------------------------------------------------------------------------
call :step "Cleaning up"
rmdir /S /Q "%WORK%" >nul 2>&1
del /Q "%LOG%" >nul 2>&1
call :done "Temporary files removed"

echo.
echo   ============================================================
echo    PHOTONE IS INSTALLED
echo    Start it from the Desktop or the Start menu.
echo   ============================================================
echo.
choice /C YN /N /M "  Start Photone now? [Y/N] "
rem (Through Explorer: started from here it would run as administrator.)
if not errorlevel 2 explorer.exe "%PHOTONE_DEST%\Photone.exe"
exit /b 0

rem ---- asking for permission ----------------------------------------------------------------
:elevate
echo.
echo   PHOTONE SETUP
echo   Windows will now ask for permission. Choose Yes: setup carries on in a new window.
powershell -NoProfile -Command "Start-Process -FilePath $env:PHOTONE_SELF -ArgumentList $env:PASS -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    color 0C
    echo   Permission was not given: nothing was changed.
    pause
)
color
exit /b

rem ---- uninstall ----------------------------------------------------------------------------
:uninstall
rem A file cannot delete the folder it is running from: carry on from a copy elsewhere.
if /I "%~dp0"=="%PHOTONE_DEST%\" (
    copy /Y "%~f0" "%TEMP%\photone-uninstall.bat" >nul
    start "Photone Setup" "%TEMP%\photone-uninstall.bat" /uninstall /elevated
    exit /b
)
echo.
echo   REMOVING PHOTONE ...
:closed_too
tasklist /FI "IMAGENAME eq Photone.exe" 2>nul | find /I "Photone.exe" >nul
if not errorlevel 1 (
    echo   Photone is running. Close it, then press a key.
    pause >nul
    goto :closed_too
)
del /Q "%DESKTOP%" "%MENU%" >nul 2>&1
rmdir /S /Q "%PHOTONE_DEST%" >nul 2>&1
reg delete "%KEY%" /f >nul 2>&1
if exist "%PHOTONE_DEST%" (
    echo   Some files could not be removed: !PHOTONE_DEST!
) else (
    echo   Photone is removed.
)
echo   Your photos were never touched. The catalog of your edits and the settings are kept
echo   in %LOCALAPPDATA%\photone, should you install Photone again.
echo.
pause
exit /b 0

rem ---- the lines a step prints ---------------------------------------------------------------
:step
set /a STEP+=1
echo.
echo   [!STEP!/%STEPS%] %~1 ...
exit /b

:done
echo         OK - %~1
exit /b

:failed
color 0C
echo.
echo   ============================================================
echo    SETUP STOPPED at step !STEP! of %STEPS%
echo    !WHY!
echo   ============================================================
if exist "%LOG%" (
    echo.
    echo   The last lines of what was tried:
    powershell -NoProfile -Command "Get-Content -LiteralPath $env:LOG -Tail 12 | ForEach-Object { '    ' + $_ }" 2>nul
    echo.
    echo   All of it: !LOG!
)
if exist "%WORK%" rmdir /S /Q "%WORK%" >nul 2>&1
echo.
echo   Nothing was left half installed that a second run does not put right.
echo   Help: https://github.com/TominoCZ/Photone/issues
echo.
pause
exit /b 1
