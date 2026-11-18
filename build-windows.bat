@echo off
rem Make the Windows build of Photone in .\bin (scripts\build_windows.py says what is in it).
rem Needs Python 3.11 or later; uv, where there is one, brings its own.
where uv >nul 2>nul && (uv run --no-project --python 3.13 python "%~dp0scripts\build_windows.py" %* & goto :done)
where py >nul 2>nul && (py -3 "%~dp0scripts\build_windows.py" %* & goto :done)
python "%~dp0scripts\build_windows.py" %*
:done
if errorlevel 1 pause
