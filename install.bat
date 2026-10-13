@echo off
setlocal
set "DEST=%LOCALAPPDATA%\Plutonium\storage\t6\scripts\zm"
set "PLAYERS=%LOCALAPPDATA%\Plutonium\storage\t6\players"

if not exist "%DEST%" mkdir "%DEST%"

copy /y "%~dp0zm_allparts_hud.gsc" "%DEST%\" >nul

if errorlevel 1 (
    echo.
    echo  FAILED to copy the file.
    echo  Try running this file as Administrator (right-click - Run as administrator).
    echo.
    pause
    exit /b 1
)

rem ----- set the keys: TAB = parts panel (hold), B = scoreboard -----
call :setbinds "%PLAYERS%\bindings_zm.bdg"

for /d %%D in ("%PLAYERS%\mods\*") do call :setbinds "%%~fD\bindings_zm.bdg"

echo.
echo  ============================================================
echo   INSTALLED!
echo.
echo   Script copied to:
echo     %DEST%\zm_allparts_hud.gsc
echo.
echo   Keys set (old keys backed up next to each file as
echo   bindings_zm.bdg.allparts.bak):
echo     TAB = parts panel  (hold to show, release to hide)
echo     B   = scoreboard
echo.
echo   Now COMPLETELY close Plutonium and Black Ops II,
echo   then start the game again and play Zombies on:
echo   Tranzit, Die Rise or Buried.
echo.
echo   In game:
echo     - Carry parts as usual. A build table only builds once you
echo       are carrying ALL the parts still needed for that buildable;
echo       with the full set, one hold on USE builds the whole thing.
echo     - Hold TAB to show the parts panel, release to hide it.
echo     - Picking a part up shows a readout (icon + "1/3 parts") in
echo       the top-left, in the game's small HUD font. Optional size
echo       tweak in the console (1 = default):
echo         allparts_pickup_scale 1
echo.
echo   If holding TAB does nothing, open the console (the ~ key)
echo   and type these two lines:
echo     bind TAB "+switchseat"
echo     bind B   "+scores"
echo.
echo   To remove the mod later, delete the .gsc file and restore
echo   the .allparts.bak key files.
echo  ============================================================
echo.
pause
exit /b 0

:setbinds
set "BDG=%~1"
if not exist "%BDG%" exit /b 0
if not exist "%BDG%.allparts.bak" copy /y "%BDG%" "%BDG%.allparts.bak" >nul
findstr /v /i /b /c:"bind TAB " "%BDG%" > "%BDG%.tmp"
findstr /v /i /b /c:"bind B " "%BDG%.tmp" > "%BDG%.tmp2"
del "%BDG%.tmp" >nul 2>nul
echo bind TAB "+switchseat" >> "%BDG%.tmp2"
echo bind B   "+scores" >> "%BDG%.tmp2"
move /y "%BDG%.tmp2" "%BDG%" >nul
exit /b 0
