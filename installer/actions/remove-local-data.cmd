@echo off
rem TigerSetup post-uninstall action "remove-local-data" (installer\TigerSetup.toml).
rem
rem An explicit uninstall removes what TigerMarkView wrote for the Windows account that runs it:
rem   %LOCALAPPDATA%\TigerMarkView   settings, the Open Recent list included, and the WebView2 profiles
rem   %TEMP%\TigerMarkView           the generated preview, Help and PDF export pages
rem
rem TigerSetup runs uninstall-phase actions on an uninstall only. An upgrade never runs them, so an
rem upgrade keeps all of this. rmdir /s removes a junction or symbolic link it finds without following
rem it, so nothing outside these two folders is touched. The viewer has been closed by the time this
rem runs, but its WebView2 processes can take a moment to release their files, hence the retries.
rem
rem Exit codes: 0 both folders are gone (or never existed), 1 one is still there, 2 no profile folders.
setlocal
if not defined LOCALAPPDATA exit /b 2
if not defined TEMP exit /b 2

set "data=%LOCALAPPDATA%\TigerMarkView"
set "pages=%TEMP%\TigerMarkView"
set attempts=0

:remove
if exist "%data%\" rmdir /s /q "%data%" 2>nul
if exist "%pages%\" rmdir /s /q "%pages%" 2>nul
if not exist "%data%\" if not exist "%pages%\" goto removed
set /a attempts+=1
if %attempts% geq 10 goto left
ping -n 2 127.0.0.1 >nul
goto remove

:removed
echo Removed TigerMarkView's local data: "%data%" and "%pages%".
exit /b 0

:left
if exist "%data%\" echo Could not remove "%data%"; something still holds files in it.
if exist "%pages%\" echo Could not remove "%pages%"; something still holds files in it.
exit /b 1
