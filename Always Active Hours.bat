@echo off & for /f "tokens=2 delims=:" %%a in ('chcp') do set /a "codepage=%%a" & chcp 65001 >nul & ( reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v ACP 2>nul | findstr /c:" 932" /c:" 936" /c:" 949" /c:" 950" /c:" 1361" >nul ) && ( goto :eol_verify_dbcs ) || goto :eol_verify
:: Store the original code page, change the code page to UTF-8, read system ANSI code page (ACP), flag DBCS (JP/CN/KR/TW/KJ) and verify the line endings

:: ========== ========== ========== ========== ==========

:: Version: 1.0
:: Filename: Always Active Hours.bat
:: Written by: Brogan Scott Houston McIntyre

:: ========== ========== ========== ========== ==========

:: The main Always Active Hours script
:main
setlocal enabledelayedexpansion

:: Default exit code
set "EXIT_CODE=0"

:: ========== ========== ========== ========== ==========

ver | findstr /r "10\.0\.[0-9]*" >nul || (
	echo Error: Unsupported Windows version.
	set "EXIT_CODE=1"
	pause
	goto end
)

:: ========== ========== ========== ========== ==========

:: Default flags
set "asAdministrator=false"
set "asInstall=false"
set "asUninstall=false"
set "asTask=false"
set "asQuiet=false"
set "silent=false"

:: Check for administrator privileges
NET SESSION >nul 2>&1
if %errorlevel% EQU 0 set "asAdministrator=true"

:: Parse command-line switches
for %%A in (%*) do (
	:: Detect if installing
	if /I "%%~A"=="/install" set "asInstall=true"
	if /I "%%~A"=="/enable" set "asInstall=true"

	:: Detect if uninstalling
	if /I "%%~A"=="/uninstall" (
		set "asInstall=true"
		set "asUninstall=true"
	)
	if /I "%%~A"=="/disable" (
		set "asInstall=true"
		set "asUninstall=true"
	)

	:: Detect if running as a scheduled task
	if /I "%%~A"=="/task" set "asTask=true"

	:: Detect if running quietly
	if /I "%%~A"=="/q" set "asQuiet=true"
	if /I "%%~A"=="/quiet" set "asQuiet=true"
)

if "%asTask%"=="true" set "silent=true"
if "%asQuiet%"=="true" set "silent=true"

:: ==========

:: Reject non-administrators
if "%asAdministrator%"=="false" (
	if "%silent%"=="true" goto end
	if "%asUninstall%"=="true" (
		echo Error: This script must be uninstalled as an administrator.
		set "EXIT_CODE=2"
		goto end
	)
	if "%asInstall%"=="true" (
		echo Error: This script must be installed as an administrator.
		set "EXIT_CODE=2"
		goto end
	)
	echo Error: This script must be run as an administrator.
	echo Right-click the script and select "Run as Administrator."
	pause
	goto end
)

:: ========== ========== ========== ========== ==========

:: If running as a scheduled task, go straight to shift the active hours
if "%asTask%"=="true" goto shift_hours

:: ~~~~~

:: Set task variables
set "taskName=Always Active Hours"
set "scriptPath=%~f0"
set "targetDir=%ProgramData%\AlwaysActiveHours"
set "xmlPath=%temp%\AlwaysActiveHours.xml"
set "taskErrorLog=%temp%\schtasks_error.log"

if "%asUninstall%"=="true" goto disable_task
if "%asInstall%"=="true" goto enable_task

:: ~~~~~

:: If running in quiet mode, the default is to shift the active hours
if "%asQuiet%"=="true" goto shift_hours

:: ========== ========== ========== ========== ==========

title Always Active Hours Configurator

:: Set column and row dimensions
mode con: cols=55 lines=28

:: Obtain the escape character and store it in ESC
for /f "delims=" %%A in ('echo prompt $E^| cmd') do set "ESC=%%A"

:: ==========

:: Retrieve the EditionID from the registry
call :read_sz "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "EditionID" edition

:: Trim leading spaces
for /f "tokens=* delims= " %%S in ("%edition%") do set "edition=%%S"

:: Detect Home SKUs by exact match
set "homeEdition=0"
for %%E in (Core CoreN CoreSingleLanguage CoreSingleLanguageN CoreCountrySpecific) do (
	if /i "%edition%"=="%%E" set "homeEdition=1"
)

:: ==========

set "dashLine=-------------------------------------------------------"

goto menu

:: ========== ========== ========== ========== ==========

:: :key_exists <reg path> <outVar>
:key_exists

setlocal
reg query "%~1" >nul 2>&1
endlocal & if %errorlevel%==0 (set "%~2=1") else (set "%~2=0")

goto :eof

:: ~~~~~~~~~~

:: :value_exists "<key>" "<valueName>" <outVarNumeric>
:value_exists

setlocal EnableDelayedExpansion
reg query "%~1" /v "%~2" /reg:64 >nul 2>&1 || reg query "%~1" /v "%~2" >nul 2>&1
set "rc=!errorlevel!"
endlocal & if "%rc%"=="0" (set "%~3=1") else (set "%~3=0")

goto :eof

:: ~~~~~~~~~~

:: :value_exists_bool "<key>" "<valueName>" <outVarBool>
:value_exists_bool

setlocal
call :value_exists "%~1" "%~2" _vxb_rc
endlocal & if "%_vxb_rc%"=="1" (set "%~3=true") else (set "%~3=false")

goto :eof

:: ~~~~~~~~~~

:: :read_dword "<key>" "<valueName>" <outVar> <default>
:read_dword

setlocal EnableExtensions DisableDelayedExpansion
set "rk=%~1" & set "vn=%~2" & set "def=%~4"
set "type=" & set "val="

:: Read the value (use 64-bit view to avoid WOW64 redirect on x64)
for /f "skip=2 tokens=2,*" %%A in ('
	reg query "%rk%" /v "%vn%" /reg:64 2^>nul
') do (
		set "type=%%A"
		set "val=%%B"
)

:: Fallback to default if not found
if not defined val (
	for /f "skip=2 tokens=2,*" %%A in ('
		reg query "%rk%" /v "%vn%" 2^>nul
	') do (
		set "type=%%A"
		set "val=%%B"
	)
)

:: If still missing, return the caller-provided default
if not defined val (
	endlocal & set "%~3=%def%" & goto :eof
)

:: reg output for REG_DWORD is typically "0x######## (####)"
:: Keep only the first token to drop the "(####)" decimal echo
for /f %%D in ("%val%") do set "val=%%D"

:: Convert to decimal. `set /a` accepts hex (0x...) and decimal
:: On conversion failure, fall back to the default
2>nul set /a dec=%val%+0
if errorlevel 1 set "dec=%def%"

endlocal & set "%~3=%dec%"

goto :eof

:: ~~~~~~~~~~

:: :read_sz <key> <ValueName> <outVar>
:read_sz

setlocal EnableExtensions DisableDelayedExpansion
set "out="

for /f "tokens=2,*" %%A in ('
	reg query "%~1" /v "%~2" /reg:64 2^>nul ^| findstr /i "REG_SZ REG_EXPAND_SZ"
') do set "out=%%B"

if not defined out (
	for /f "tokens=2,*" %%A in ('
		reg query "%~1" /v "%~2" 2^>nul ^| findstr /i "REG_SZ REG_EXPAND_SZ"
	') do set "out=%%B"
)

:: Trim leading spaces
setlocal EnableDelayedExpansion
for /f "tokens=* delims= " %%S in ("!out!") do set "out=%%S"
endlocal & set "out=%out%"

endlocal & set "%~3=%out%"
goto :eof

:: ========== ========== ========== ========== ==========

:title

cls
setlocal EnableDelayedExpansion
set "input=%~1"

:: Trim spaces
for /f "tokens=* delims= " %%A in ("%input%") do set "msg=%%A"

:: Truncate to fit box
set "msg=!msg:~0,51!"

:: Measure length manually
set "len=0"
for /l %%i in (0,1,50) do (
	if not "!msg:~%%i,1!"=="" set /a len+=1
)

:: Calculate padding
set /a innerWidth=51
set /a padRight=(innerWidth - len) / 2
set /a padLeft=innerWidth - len - padRight

:: Pad and print
set "spaces=                                                       "
set "line=║ !spaces:~0,%padLeft%!%msg%!spaces:~0,%padRight%! ║"

echo ╔═════════════════════════════════════════════════════╗
echo !line!
echo ╚═════════════════════════════════════════════════════╝
echo.

endlocal

goto :eof

:: ========== ========== ========== ========== ==========

:get_active_hours_range

:: Fetch Active Hours Max Range if set by policy
call :read_dword "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "ActiveHoursMaxRange" activeHoursMaxRangeDec 18

:: Clamp range between 8 and 18 hours (Windows defaults to 18 if out of range)
if %activeHoursMaxRangeDec% LSS 8 (
	set activeHoursMaxRangeDec=18
)
if %activeHoursMaxRangeDec% GTR 18 (
	set activeHoursMaxRangeDec=18
)

goto :eof

:: ========== ========== ========== ========== ==========

:convert_to_ampm

:: Convert 24-hour time to AM/PM format
set hour=%1
set /a hour=hour +0
if %hour% LSS 12 (
	set suffix=AM
	if %hour% EQU 0 set hour=12
) else (
	set suffix=PM
	if %hour% GTR 12 set /a hour-=12
)
set "%2=%hour%%suffix%"

goto :eof

:: ========== ========== ========== ========== ==========

:parse_time_string
set "now=%~1"
goto :parse_time_core

:parse_system_time
set "now=%TIME%"

:parse_time_core
setlocal EnableDelayedExpansion
set "invalidTime=0"

:: Split H:M:S and optional AM/PM
for /f "tokens=1-4 delims=:., " %%a in ("%now%") do (
	set "h=%%a"
	set "m=%%b"
	set "s=%%c"
	set "ampm=%%d"
)

:: Trim leading spaces
set "h=!h: =!"
set "m=!m: =!"
set "s=!s: =!"
set "ampm=!ampm: =!"

:: Normalize numbers
2>nul (
	set /a H=1!h!-100
	set /a M=1!m!-100
	set /a S=1!s!-100
)

if not defined H set "invalidTime=1" & set "H=0"
if not defined M set "invalidTime=1" & set "M=0"
if not defined S set "invalidTime=1" & set "S=0"

:: Adjust for AM/PM if token captured
if defined ampm (
	if /i not "!ampm!"=="AM" if /i not "!ampm!"=="PM" set "invalidTime=1"
	if /i "!ampm!"=="PM" if !H! LSS 12 set /a H+=12
	if /i "!ampm!"=="AM" if !H! EQU 12 set /a H=0
)

:: Range checks and clamp
if !H! LSS 0 (set "invalidTime=1" & set "H=0")
if !H! GTR 23 (set "invalidTime=1" & set "H=23")
if !M! LSS 0 (set "invalidTime=1" & set "M=0")
if !M! GTR 59 (set "invalidTime=1" & set "M=0")
if !S! LSS 0 (set "invalidTime=1" & set "S=0")
if !S! GTR 59 (set "invalidTime=1" & set "S=0")

:: Two-digit pads
if !H! LSS 10 (set "HH=0!H!") else set "HH=!H!"
if !M! LSS 10 (set "MM=0!M!") else set "MM=!M!"
if !S! LSS 10 (set "SS=0!S!") else set "SS=!S!"

:: End the local environment and return the values to the global scope
endlocal & (
	set "HOUR=%H%"
	set "MINUTE=%M%"
	set "SECOND=%S%"
	set "hh=%HH%"
	set "mm=%MM%"
	set "ss=%SS%"
	set "INVALID_TIME=%invalidTime%"
)

goto :eof

:: ========== ========== ========== ========== ==========

:parse_system_date

setlocal EnableDelayedExpansion

:: Retrieve and clean Regional sShortDate
for /f "tokens=2,*" %%A in ('reg query "HKCU\Control Panel\International" /v sShortDate 2^>nul ^| findstr /i "sShortDate"') do (
	set "shortDateFormat=%%B"
)
set "shortDateFormat=!shortDateFormat:REG_SZ=!"
for /f "tokens=* delims= " %%C in ("!shortDateFormat!") do set "shortDateFormat=%%C"

:: Get raw line for sDate
for /f "tokens=*" %%L in ('reg query "HKCU\Control Panel\International" /v sDate ^| findstr /i "sDate"') do (
	set "regLine=%%L"
)

:: Remove everything up to and including "REG_SZ" (preserve what's after)
set "dateSeparator=!regLine:*REG_SZ =!"
set "dateSeparator=!dateSeparator:~3!"

for /f "tokens=* delims= " %%C in ("!shortDateFormat!") do set "shortDateFormat=%%C"

:: Trim the date separator only if it's not a literal space
if not "!dateSeparator!"==" " (
	for /f "tokens=* delims= " %%C in ("!dateSeparator!") do set "dateSeparator=%%C"
)

:: Build the Date Stem, replacing patterns with single letters: 'yyyy'/'yy' -> Y, 'MM' -> M, 'dd' -> D
set "dateStem=!shortDateFormat!"
set "dateStem=!dateStem:yyyy=Y!"
set "dateStem=!dateStem:yy=Y!"
set "dateStem=!dateStem:MMMM=M!"
set "dateStem=!dateStem:MMM=M!"
set "dateStem=!dateStem:MM=M!"
set "dateStem=!dateStem:dddd=D!"
set "dateStem=!dateStem:ddd=D!"
set "dateStem=!dateStem:dd=D!"
set "dateStem=!dateStem:d=D!"

:: Remove any occurrences of the separator and common delimiters
set "dateStem=!dateStem:%dateSeparator%=!"
set "dateStem=!dateStem:/=!"
set "dateStem=!dateStem:-=!"
set "dateStem=!dateStem:.=!"
set "dateStem=!dateStem: =!"

:: Prepare the Date Core from %DATE%
set "dateCore=%DATE%"

:: Strip the weekday prefix if present
if not "%dateCore%"=="%dateCore: =%" (
	for /f "tokens=1,* delims= " %%X in ("%dateCore%") do (
		set "weekday=%%X"
		set "dateCore=%%Y"
	)
)

:: Split Date Core into Parts
for /f "tokens=1-3 delims=%dateSeparator%" %%A in ("%dateCore%") do (
	set "part1=%%A"
	set "part2=%%B"
	set "part3=%%C"
)

:: Map Tokens to Year, Month, Day Using the Date Stem
set "order=!dateStem:~0,3!"

:: Initialize date variables
set "year="
set "month="
set "day="

:: Map token 1
if /i "!order:~0,1!"=="Y" (set "year=!part1!")
if /i "!order:~0,1!"=="M" (set "month=!part1!")
if /i "!order:~0,1!"=="D" (set "day=!part1!")

:: Map token 2
if /i "!order:~1,1!"=="Y" (set "year=!part2!")
if /i "!order:~1,1!"=="M" (set "month=!part2!")
if /i "!order:~1,1!"=="D" (set "day=!part2!")

:: Map token 3
if /i "!order:~2,1!"=="Y" (set "year=!part3!")
if /i "!order:~2,1!"=="M" (set "month=!part3!")
if /i "!order:~2,1!"=="D" (set "day=!part3!")

:: If the year is 2 digits, prefix it with "20"
if "!year:~2!"=="" (
	set "year=20!year!"
)

:: Convert month names to numbers if necessary...

:: ~~~~~~~~~~ ~~~~~~~~~~ ~~~~~~~~~~

:: English
if /i "!month!"=="Jan" set "month=1"
if /i "!month!"=="Feb" set "month=2"
if /i "!month!"=="Mar" set "month=3"
if /i "!month!"=="Apr" set "month=4"
if /i "!month!"=="May" set "month=5"
if /i "!month!"=="Jun" set "month=6"
if /i "!month!"=="Jul" set "month=7"
if /i "!month!"=="Aug" set "month=8"
if /i "!month!"=="Sep" set "month=9"
if /i "!month!"=="Oct" set "month=10"
if /i "!month!"=="Nov" set "month=11"
if /i "!month!"=="Dec" set "month=12"

:: ~~~~~~~~~~ ~~~~~~~~~~ ~~~~~~~~~~

:: Preserve original value
set "value=!month!"
set "invalidMonth=0"

:: Convert to numbers to remove any existing leading zeros, then pad to two digits if needed
if "!month:~0,1!"=="0" set "month=!month:~1!"

:: Try arithmetic eval, will fail if not numeric
if "%month%" LSS "0" set "invalidMonth=1"
if %month% GEQ 13 set "invalidMonth=1"
if %month% LSS 10 set "month=0%month%"

:: Decimal interpretation for days
if "!day:~0,1!"=="0" set "day=!day:~1!"
if %day% LSS 10 set "day=0%day%"

:: End the local block and return results in global variables
endlocal & (
	set "YEAR=%year%"
	set "MONTH=%month%"
	set "DAY=%day%"
	set "INVALID_MONTH=%invalidMonth%"
)

goto :eof

:: ========== ========== ========== ========== ==========

:check_pending_reboot

setlocal EnableDelayedExpansion

:: Reset all of the reboot flags
set "CBS=0" & set "WU=0" & set "PFR=0" & set "REBOOT_PENDING=0"

:: Check the registry for the reboot flags
call :key_exists "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" CBS
call :key_exists "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" WU
call :value_exists "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" "PendingFileRenameOperations" PFR

:: If any flag is 1, set overall pending
if !CBS! EQU 1 set "REBOOT_PENDING=1"
if !WU! EQU 1 set "REBOOT_PENDING=1"
if !PFR! EQU 1 set "REBOOT_PENDING=1"

endlocal & (
	set "CBS=%CBS%"
	set "WU=%WU%"
	set "PFR=%PFR%"
	set "REBOOT_PENDING=%REBOOT_PENDING%"
)

goto :eof

:: ========== ========== ========== ========== ==========

:menu

:: Check if the scheduled task exists
schtasks /query /tn "%taskName%" >nul 2>&1
if %errorlevel% EQU 0 (
	set "taskExists=true"
) else (
	set "taskExists=false"
)

:: Fetch current active hours from the registry
call :read_dword "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "ActiveHoursStart" activeStart 8
call :read_dword "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "ActiveHoursEnd" activeEnd 18

:: Convert active hours to AM/PM format
call :convert_to_ampm %activeStart% activeStartDisplay
call :convert_to_ampm %activeEnd% activeEndDisplay

:: Fetch No Auto Reboot settings
call :value_exists_bool "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" noRebootPolicy

:: Resolve the effective active hours range (policy or default)
call :get_active_hours_range

:: Check the current pending reboot state
call :check_pending_reboot

if "%REBOOT_PENDING%"=="1" (
	:: Parse the time and date strings by reading the language settings
	call :parse_system_time
	call :parse_system_date
)

:: ==========

:menu_display

:: Reset choice variable
set "choice="

:: Display the menu
call :title "Always Active Hours Configurator"

if defined activeStartDisplay if defined activeEndDisplay (
	call :display_active_hours %activeStart% %activeEnd%
	echo.
	set "space="
	if %activeStart% LSS 10 if %activeEnd% LSS 10 set "space=!space! "
	if %activeStart% LSS 10 if %activeEnd% GEQ 13 if %activeEnd% LEQ 20 set "space=!space! "
	if %activeStart% GEQ 13 if %activeStart% LEQ 21 if %activeEnd% LSS 10 set "space=!space! "
	if %activeStart% GEQ 13 if %activeStart% LEQ 21 if %activeEnd% GEQ 13 if %activeEnd% LEQ 21 set "space=!space! "
	echo !space!Your current active hours are set between %activeStartDisplay% and %activeEndDisplay%
) else (
	echo Error: Unable to fetch active hours settings.
)

if not "%activeHoursMaxRangeDec%"=="18" (
	if %activeHoursMaxRangeDec% LSS 10 (
		set "space=     "
	) else (
		set "space=    "
	)
	echo !space!Your active hours range is limited to %activeHoursMaxRangeDec% hours
)

echo.
if "%REBOOT_PENDING%"=="1" (
	echo              A reboot is currently pending
) else (
	echo          System is in a clean reboot state
)

echo.
echo %dashLine%
echo.

:: =====

if "%taskExists%"=="true" (
	echo   1. Disable Scheduled Task
) else (
	echo   1. Enable Scheduled Task
)

echo   2. Shift Active Hours

if "%noRebootPolicy%"=="true" (
	echo   3. Disable No Auto Reboot Policy
) else (
	if "%homeEdition%"=="0" (
		echo   3. Enable No Auto Reboot Policy
	) else (
		echo   3. %ESC%[90mEnable No Auto Reboot Policy%ESC%[0m
	)
)

if "%homeEdition%"=="0" (
	echo   4. Delay Aggressive Updates
) else (
	echo   4. %ESC%[90mDelay Aggressive Updates%ESC%[0m
)

echo   5. Required Reboots
echo   6. %ESC%[4mR%ESC%[0mefresh
echo   7. %ESC%[4mE%ESC%[0mxit

:: =====

echo.
echo %dashLine%
echo.
set /p "choice=  Enter your choice (1-7): "

if "%choice%"=="1" goto toggle_task
if "%choice%"=="2" goto shift_hours
if "%choice%"=="3" (
	if "%homeEdition%"=="0" (
		goto toggle_no_reboot
	) else (
		if "%noRebootPolicy%"=="true" (
			goto toggle_no_reboot
		) else (
			goto toggle_no_reboot_home
		)
	)
)
if "%choice%"=="4" goto delay_updates
if "%choice%"=="5" goto required_reboots
if "%choice%"=="6" goto menu
if "!choice!"=="r" goto menu
if "%choice%"=="7" goto end
if "!choice!"=="e" goto end
goto menu_display

:: ========== ========== ========== ========== ==========

:display_active_hours
:: Input: %1 = start hour, %2 = end hour

:: Initialize variables
setlocal enabledelayedexpansion
set "bar=   "
set "labels=    "
set "arrow=   "

set /a start=%1
set /a end=%2

:: Parse the system time to set the current hour
call :parse_system_time

:: Normalize end hour for wrap-around
if %end% LSS %start% (
	set /a normalized_end=%end%+24
) else (
	set /a normalized_end=%end%
)

:: Generate the bar and arrow lines
for /l %%H in (0,1,23) do (
	set /a h=%%H
	set /a normalized_hour=h
	if !h! LSS %start% set /a normalized_hour=h+24

	if %%H EQU !HOUR! (
		if !normalized_hour! GEQ %start% if !normalized_hour! LSS %normalized_end% (
			set "block=█" :: Active current hour
		) else (
			set "block=▒" :: Inactive current hour
		)
		set "arrow=!arrow! ↓"
	) else (
		if !normalized_hour! GEQ %start% if !normalized_hour! LSS %normalized_end% (
			set "block=▓" :: Active hours
		) else (
			set "block=░" :: Inactive hours
		)
		set "arrow=!arrow!  "
	)

	set "bar=!bar! !block!"
)

:: Generate hour labels
for /l %%L in (0,3,21) do (
	if %%L LSS 10 (
		set "label= 0%%L"
	) else (
		set "label= %%L"
	)
	if %%L NEQ 21 (
		set "labels=!labels!└!label!  "
	) else (
		set "labels=!labels!└!label!"
	)
)

:: Display the arrow, bar and label lines
echo !arrow!
echo !bar!
echo !labels!
endlocal

goto :eof

:: ========== ========== ========== ========== ==========

:enable_task

:: Check if the scheduled task exists
schtasks /query /tn "%taskName%" >nul 2>&1
if %errorlevel% EQU 0 (
	if "%silent%"=="false" (
		echo Always Active Hours is already enabled.
	)
	goto end
) else (
	set "taskExists=false"
	goto toggle_task
)

:: ==========

:disable_task

:: Check if the scheduled task exists
schtasks /query /tn "%taskName%" >nul 2>&1
if %errorlevel% NEQ 0 (
	if "%silent%"=="false" (
		echo Always Active Hours is already disabled.
	)
	goto end
) else (
	set "taskExists=true"
	goto toggle_task
)

:: ==========

:toggle_task

if "%asInstall%"=="false" (
	if "%silent%"=="false" (
		:: Display the Title
		call :title "Scheduled Task Settings"
	)
)

if "%taskExists%"=="true" (
	if "%silent%"=="false" (
		echo Preparing uninstallation:
		echo Removing the scheduled task...
	)

	:: Remove the scheduled task
	schtasks /delete /tn "%taskName%" /f >nul 2>&1

	call :uninstall

	:: Set the task action
	set "taskAction=remove"
	goto task_check
)

:: Parse the time and date strings by reading the language settings
call :parse_system_time
call :parse_system_date

if "%INVALID_MONTH%"=="1" (
	set "MONTH=01"
)

:: Format the date-time as YYYY-MM-DDTHH:mm:ss
set formattedDate=%YEAR%-%MONTH%-%DAY%T%hh%:%mm%:%ss%

call :install

if "%silent%"=="false" (
	echo Enabling active hours...
)

:: Ensure SmartActiveHoursState is set to 0
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v SmartActiveHoursState /t REG_DWORD /d 0 /f >nul
if %errorlevel% NEQ 0 (
	if "%silent%"=="false" (
		echo Error: Failed to set SmartActiveHoursState to 0.
		echo.
		echo %dashLine%
		echo.
		pause
		goto menu
	) else (
		goto end
	)
)

if "%silent%"=="false" (
	echo Creating the scheduled task...
)

rem Create temporary XML file
(
	echo ^<?xml version="1.0" encoding="UTF-16"?^>
	echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
	echo   ^<RegistrationInfo^>
	echo     ^<Date^>%formattedDate%^</Date^>
	echo     ^<Author^>%username%^</Author^>
	echo     ^<URI^>\%taskName%^</URI^>
	echo   ^</RegistrationInfo^>
	echo   ^<Triggers^>
	echo     ^<RegistrationTrigger^>
	echo       ^<Enabled^>true^</Enabled^>
	echo     ^</RegistrationTrigger^>
	echo     ^<BootTrigger^>
	echo       ^<Enabled^>true^</Enabled^>
	echo     ^</BootTrigger^>
	echo     ^<CalendarTrigger^>
	echo       ^<Repetition^>
	echo         ^<Interval^>PT1H^</Interval^>
	echo         ^<StopAtDurationEnd^>false^</StopAtDurationEnd^>
	echo       ^</Repetition^>
	echo       ^<StartBoundary^>%YEAR%-%MONTH%-%DAY%T00:00:00^</StartBoundary^>
	echo       ^<Enabled^>true^</Enabled^>
	echo       ^<ScheduleByDay^>
	echo         ^<DaysInterval^>1^</DaysInterval^>
	echo       ^</ScheduleByDay^>
	echo     ^</CalendarTrigger^>
	echo     ^<EventTrigger^>
	echo       ^<Enabled^>true^</Enabled^>
	echo       ^<Subscription^>^&lt;QueryList^&gt;^&lt;Query Id="0" Path="System"^&gt;^&lt;Select Path="System"^&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]^&lt;/Select^&gt;^&lt;/Query^&gt;^&lt;/QueryList^&gt;^</Subscription^>
	echo     ^</EventTrigger^>
	echo     ^<EventTrigger^>
	echo       ^<Enabled^>true^</Enabled^>
	echo       ^<Subscription^>^&lt;QueryList^&gt;^&lt;Query Id="0" Path="System"^&gt;^&lt;Select Path="System"^&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=507]]^&lt;/Select^&gt;^&lt;/Query^&gt;^&lt;/QueryList^&gt;^</Subscription^>
	echo     ^</EventTrigger^>
	echo   ^</Triggers^>
	echo   ^<Principals^>
	echo     ^<Principal id="Author"^>
	echo       ^<UserId^>S-1-5-18^</UserId^>
	echo       ^<LogonType^>Password^</LogonType^>
	echo       ^<RunLevel^>HighestAvailable^</RunLevel^>
	echo     ^</Principal^>
	echo   ^</Principals^>
	echo   ^<Settings^>
	echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^>
	echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^>
	echo     ^<StopIfGoingOnBatteries^>true^</StopIfGoingOnBatteries^>
	echo     ^<AllowHardTerminate^>true^</AllowHardTerminate^>
	echo     ^<StartWhenAvailable^>true^</StartWhenAvailable^>
	echo     ^<RunOnlyIfNetworkAvailable^>false^</RunOnlyIfNetworkAvailable^>
	echo     ^<IdleSettings^>
	echo       ^<StopOnIdleEnd^>true^</StopOnIdleEnd^>
	echo       ^<RestartOnIdle^>false^</RestartOnIdle^>
	echo     ^</IdleSettings^>
	echo     ^<AllowStartOnDemand^>true^</AllowStartOnDemand^>
	echo     ^<Enabled^>true^</Enabled^>
	echo     ^<Hidden^>true^</Hidden^>
	echo     ^<RunOnlyIfIdle^>false^</RunOnlyIfIdle^>
	echo     ^<WakeToRun^>false^</WakeToRun^>
	echo     ^<ExecutionTimeLimit^>PT30S^</ExecutionTimeLimit^>
	echo     ^<Priority^>7^</Priority^>
	echo   ^</Settings^>
	echo   ^<Actions Context="Author"^>
	echo     ^<Exec^>
	echo       ^<Command^>"%targetDir%\Always Active Hours.bat"^</Command^>
	echo       ^<Arguments^>/task^</Arguments^>
	echo     ^</Exec^>
	echo   ^</Actions^>
	echo ^</Task^>
) > "%xmlPath%"

:: Verify the existence of the XML file
if not exist "%xmlPath%" (
	if "%silent%"=="false" (
		echo XML file "%xmlPath%" does not exist.
		echo Unable to create the scheduled task without the XML configuration.
		echo.
		echo %dashLine%
		echo.
		pause
		goto menu
	) else (
		goto end
	)
)

:: Register the task using the XML file
schtasks /create /tn "%taskName%" /xml "%xmlPath%" /ru SYSTEM /f >"%taskErrorLog%" 2>&1

:: Clean up the XML file
del "%xmlPath%" >nul 2>&1

:: Set the task action
set "taskAction=create"

goto task_check
:task_check

if "%asInstall%"=="false" (
	if "%silent%"=="false" (
		echo.
		echo %dashLine%
		echo.
	)
)

:: Check if the task action was successful or not
schtasks /query /tn "%taskName%" >nul 2>&1
if "%taskAction%"=="remove" (
	if "%silent%"=="false" (
		if %errorlevel% EQU 0 (
			echo Error: Failed to remove the scheduled task.
		) else (
			echo Scheduled task removed successfully.
		)
	)
) else (
	if "%silent%"=="false" (
		if %errorlevel% EQU 0 (
			echo Scheduled task created successfully.
		) else (
			echo Error: Failed to create the scheduled task.
			if exist "%taskErrorLog%" (
				echo.
				echo                      ERROR DETAILS
				echo =======================================================
				for /f "tokens=*" %%A in (%taskErrorLog%) do (
					set "line=%%A"
					setlocal enabledelayedexpansion
					set "line=!line:ERROR: =!"
					echo !line!
					endlocal
				)
			)
		)
	)
)

if "%asInstall%"=="true" goto end

echo.
pause
goto menu

:: ==========

:install

if "%silent%"=="false" (
	echo Preparing installation:
)

:: Check if already installed in target location
if /I "%~dp0"=="%targetDir%\" (
	if /I "%~nx0"=="Always Active Hours.bat" (
		if "%silent%"=="false" (
			echo Already installed.
		)
		goto :eof
	)
)

:: Define the destination file path
set "filePath=%targetDir%\Always Active Hours.bat"

:: Prepare the state variables
set "forceAdmin=0"
set "forceAll=0"

:: Create target directory if it doesn't exist and set SYSTEM as owner with full control
if not exist "%targetDir%" (
	if "%silent%"=="false" (
		echo Creating the installation directory...
	)
	mkdir "%targetDir%"
	icacls "%targetDir%" /setowner "*S-1-5-18" /c /q >nul
	icacls "%targetDir%" /grant "*S-1-5-18":(^OI^)(^CI^)^F /t /c /q >nul
) else (
	:: Delete existing file; if deletion fails, apply fallback permissions and try again
	if exist "%filePath%" (
		if "%silent%"=="false" (
			echo Deleting the old installation...
		)
		del /F /Q "%filePath%"
		if exist "%filePath%" (
			if "%silent%"=="false" (
				echo Applying Administrator Group privileges...
			)
			icacls "%targetDir%" /grant:r "*S-1-5-32-544":(^OI^)(^CI^)^F >nul
			set "forceAdmin=1"
			del /F /Q "%filePath%"
			if exist "%filePath%" (
				if "%silent%"=="false" (
					echo Applying All Users privileges...
				)
				icacls "%targetDir%" /grant:r "*S-1-5-32-545":(^OI^)(^CI^)^F >nul
				set "forceAll=1"
				del /F /Q "%filePath%"
			)
		)
	)
)

if "%silent%"=="false" (
	echo Copying batch file to the installation directory...
)

:: Copy the script to the target directory with /-I to force file interpretation
xcopy "%scriptPath%" "%filePath%" /Y /-I /Q >nul 2>&1

:: If the copy failed, try piping "f" to answer the prompt
if not exist "%filePath%" (
	echo f | xcopy "%scriptPath%" "%filePath%" /Y /Q >nul 2>&1
)

:: If the copy failed, try applying Administrator privileges and copy again
if not exist "%filePath%" (
	if "%forceAdmin%"=="0" (
		if "%silent%"=="false" (
			echo Applying Administrator Group privileges...
		)
		icacls "%targetDir%" /grant:r "*S-1-5-32-544":(^OI^)(^CI^)^F >nul
		set "forceAdmin=1"
		xcopy "%scriptPath%" "%filePath%" /Y /-I /Q >nul 2>&1
		if not exist "%filePath%" (
			echo f | xcopy "%scriptPath%" "%filePath%" /Y /Q >nul 2>&1
		)
	)
)

:: If still unsuccessful, try applying All Users privileges and copy again
if not exist "%filePath%" (
	if "%forceAll%"=="0" (
		if "%silent%"=="false" (
			echo Applying All Users privileges...
		)
		icacls "%targetDir%" /grant:r "*S-1-5-32-545":(^OI^)(^CI^)^F >nul
		set "forceAll=1"
		xcopy "%scriptPath%" "%filePath%" /Y /-I /Q >nul 2>&1
		if not exist "%filePath%" (
			echo f | xcopy "%scriptPath%" "%filePath%" /Y /Q >nul 2>&1
		)
	)
)

:: Clean up fallback privileges if they were applied
if "%forceAll%"=="1" (
	if "%silent%"=="false" (
		echo Removing All Users privileges...
	)
	icacls "%targetDir%" /remove "*S-1-5-32-545" >nul
)
if "%forceAdmin%"=="1" (
	if "%silent%"=="false" (
		echo Removing Administrator Group privileges...
	)
	icacls "%targetDir%" /remove "*S-1-5-32-544" >nul
)

goto :eof

:: ==========

:uninstall

:: Define the target file path
set "filePath=%targetDir%\Always Active Hours.bat"

:: Prepare the state variables
set "forceAdmin=0"
set "forceAll=0"

:: Delete the file; if deletion fails, apply fallback permissions and try again
if exist "%filePath%" (
	if "%silent%"=="false" (
		echo Deleting the batch file...
	)
	del /F /Q "%filePath%"
	if exist "%filePath%" (
		if "%silent%"=="false" (
			echo Applying Administrator Group privileges...
		)
		icacls "%targetDir%" /grant:r "*S-1-5-32-544":(^OI^)(^CI^)^F >nul
		set "forceAdmin=1"
		del /F /Q "%filePath%"
		if exist "%filePath%" (
			if "%silent%"=="false" (
				echo Applying All Users privileges...
			)
			icacls "%targetDir%" /grant:r "*S-1-5-32-545":(^OI^)(^CI^)^F >nul
			set "forceAll=1"
			del /F /Q "%filePath%"
		)
	)
)

:: If the directory is empty, remove it; otherwise, clean up fallback privileges
dir /b "%targetDir%" | findstr . >nul
if errorlevel 1 (
	if "%silent%"=="false" (
		echo Removing the installation directory...
	)
	rd "%targetDir%"
) else (
	if "%forceAll%"=="1" (
		if "%silent%"=="false" (
			echo Removing All Users privileges...
		)
		icacls "%targetDir%" /remove "*S-1-5-32-545" >nul
	)
	if "%forceAdmin%"=="1" (
		if "%silent%"=="false" (
			echo Removing Administrator Group privileges...
		)
		icacls "%targetDir%" /remove "*S-1-5-32-544" >nul
	)
)

goto :eof

:: ========== ========== ========== ========== ==========

:toggle_no_reboot

:: Display the Title
call :title "No Auto Reboot Policy Settings"

if "%noRebootPolicy%"=="true" (
	:: Disable No Auto Reboot Policy
	echo Removing No Auto Reboot policy...
	reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /f >nul 2>&1

	echo.
	echo %dashLine%
	echo.

	call :value_exists "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" result
	if !result! EQU 0 (
		echo No Auto Reboot policy has been disabled successfully.
	) else (
		echo Error: Failed to disable No Auto Reboot policy.
	)
) else (
	:: Enable No Auto Reboot Policy
	echo Adding No Auto Reboot policy...
	reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f >nul 2>&1

	echo.
	echo %dashLine%
	echo.

	call :value_exists "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" result
	if !result! NEQ 0 (
		echo No Auto Reboot policy has been enabled successfully.
	) else (
		echo Error: Failed to enable No Auto Reboot policy.
	)
)

echo.
pause
goto menu

:: ==========

:toggle_no_reboot_home

call :title "No Auto Reboot Policy Settings"

echo  This feature is not supported on Home editions.
echo.
echo  Windows 10 and 11 Home editions do not honor the
echo  NoAutoRebootWithLoggedOnUsers policy. Even if added
echo  to the registry, it will be ignored by the Windows
echo  Update system.
echo.
echo  This limitation is hardcoded and cannot be bypassed
echo  without upgrading to Windows Pro or higher.
echo.
echo %dashLine%
echo.

:: Set userInput to an empty string
set "userInput="

:: Prompt for enabling the policy (1/y/yes, 0/n/no)
set /p "userInput=Do you still want to enable this policy? (Y,N): "

:: Remove leading and trailing spaces
set "response=%userInput%"
set "response=!response: =!"

set result=-1
:: Match user input to valid responses
if /i "%response%"=="1" set result=1
if /i "%response%"=="y" set result=1
if /i "%response%"=="yes" set result=1
if /i "%response%"=="0" set result=0
if /i "%response%"=="n" set result=0
if /i "%response%"=="no" set result=0

:: Check if result was set
if "%result%"=="-1" (
	echo Invalid input. Please enter 1/Y/Yes or 0/N/No.
	pause
	goto toggle_no_reboot_home
)
if "%result%"=="0" (
	goto menu
) else (
	:: Result has been accepted
	goto toggle_no_reboot
)

:: ========== ========== ========== ========== ==========

:shift_hours

if "%silent%"=="false" (
	:: Display the Title
	call :title "Shift Active Hours"

	echo Shifting active hours...
)

:: Parse the system time to get the current hour
call :parse_system_time

:: Resolve the effective active hours range (policy or default)
call :get_active_hours_range

:: Calculate half-range (floor/ceil for odd numbers)
set /a halfLow=activeHoursMaxRangeDec / 2
set /a halfHigh=activeHoursMaxRangeDec - halfLow

:: Calculate start hour
set /a startHour=(HOUR - halfLow)
if %startHour% LSS 0 set /a startHour+=24

:: Calculate end hour
set /a endHour=(HOUR + halfHigh) %% 24

:: Write registry values
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursStart /t REG_DWORD /d %startHour% /f >nul
if "%silent%"=="false" (
	if %errorlevel% EQU 0 (
		echo ActiveHoursStart set to %startHour%
	) else (
		echo Error: Failed to set ActiveHoursStart. ErrorLevel: %errorlevel%
	)
)

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursEnd /t REG_DWORD /d %endHour% /f >nul
if "%silent%"=="false" (
	if %errorlevel% EQU 0 (
		echo ActiveHoursEnd set to %endHour%
	) else (
		echo Error: Failed to set ActiveHoursEnd. ErrorLevel: %errorlevel%
	)
)

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v UserChoiceActiveHoursStart /t REG_DWORD /d %startHour% /f >nul
if "%silent%"=="false" (
	if %errorlevel% EQU 0 (
		echo UserChoiceActiveHoursStart set to %startHour%
	) else (
		echo Error: Failed to set UserChoiceActiveHoursStart. ErrorLevel: %errorlevel%
	)
)

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v UserChoiceActiveHoursEnd /t REG_DWORD /d %endHour% /f >nul
if "%silent%"=="false" (
	if %errorlevel% EQU 0 (
		echo UserChoiceActiveHoursEnd set to %endHour%
	) else (
		echo Error: Failed to set UserChoiceActiveHoursEnd. ErrorLevel: %errorlevel%
	)
)

:: End if running as a task or in quiet mode
if "%silent%"=="true" goto end

:: Convert startHour and endHour to AM/PM format
call :convert_to_ampm %startHour% newStartDisplay
call :convert_to_ampm %endHour% newEndDisplay

echo.
echo %dashLine%
echo.

:: Display updated active hours
echo Active hours shifted to %newStartDisplay% - %newEndDisplay%.

echo.
pause
goto menu

:: ========== ========== ========== ========== ==========

:delay_updates

:: Compliance Deadline Master Toggle (0 or 1, optional, default 0)
call :read_dword "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "SetComplianceDeadline" complianceDeadline 0
if %complianceDeadline% NEQ 0 set complianceDeadline=1

:: Feature Update Delay (0–30, default 2)
set "ConfigDeadlineForFeatureUpdates=-1"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineForFeatureUpdates 2^>nul') do (
	set /a "val=%%A"
	if !val! GEQ 0 if !val! LEQ 30 (
		set "ConfigDeadlineForFeatureUpdates=!val!"
	) else (
		set "ConfigDeadlineForFeatureUpdates=2"
	)
)

:: Quality Update Delay (0–30, default 2)
set "ConfigDeadlineForQualityUpdates=-1"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineForQualityUpdates 2^>nul') do (
	set /a "val=%%A"
	if !val! GEQ 0 if !val! LEQ 30 (
		set "ConfigDeadlineForQualityUpdates=!val!"
	) else (
		set "ConfigDeadlineForQualityUpdates=2"
	)
)

:: Grace Period (0–7, default 2)
set "ConfigDeadlineGracePeriod=-1"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineGracePeriod 2^>nul') do (
	set /a "val=%%A"
	if !val! GEQ 0 if !val! LEQ 7 (
		set "ConfigDeadlineGracePeriod=!val!"
	) else (
		set "ConfigDeadlineGracePeriod=2"
	)
)

:: No Auto Reboot (0 or 1, default 0)
set "ConfigDeadlineNoAutoReboot=-1"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineNoAutoReboot 2^>nul') do (
	set /a "val=%%A"
	if !val! EQU 1 (
		set "ConfigDeadlineNoAutoReboot=1"
	) else if !val! EQU 0 (
		set "ConfigDeadlineNoAutoReboot=0"
	) else (
		set "ConfigDeadlineNoAutoReboot=0"
	)
)

:: Reset choice variable
set "choice="

:: Display the title
call :title "Delay Aggressive Updates"

if "%complianceDeadline%"=="1" (
	echo         Aggressive update deadlines are ENABLED
	echo.

	set "spaces=                                                   "

	echo ╔═════════════════════════════════════════════════════╗

	:: Feature Update Delay
	set "label=Feature Update Delay"
	set "line=║  !label!"
	set "line=!line!!spaces!"
	if %ConfigDeadlineForFeatureUpdates% NEQ -1 (
		if %ConfigDeadlineForFeatureUpdates% == 1 (
			set "value=1 day"
			set "line=!line:~0,45!  !value!"
		) else (
			set "value=%ConfigDeadlineForFeatureUpdates% days"
			if %ConfigDeadlineForFeatureUpdates% LSS 9 (
				set "line=!line:~0,44!  !value!"
			) else (
				set "line=!line:~0,43!  !value!"
			)
		)
	) else (
		set "value=2 days (default)"
		set "line=!line:~0,34!  !value!"
	)
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	echo ╟─────────────────────────────────────────────────────╢

	:: Quality Update Delay
	set "label=Quality Update Delay"
	set "line=║  !label!"
	set "line=!line!!spaces!"
	if %ConfigDeadlineForQualityUpdates% NEQ -1 (
		if %ConfigDeadlineForQualityUpdates% == 1 (
			set "value=1 day"
			set "line=!line:~0,45!  !value!"
		) else (
			set "value=%ConfigDeadlineForQualityUpdates% days"
			if %ConfigDeadlineForQualityUpdates% LSS 9 (
				set "line=!line:~0,44!  !value!"
			) else (
				set "line=!line:~0,43!  !value!"
			)
		)
	) else (
		set "value=2 days (default)"
		set "line=!line:~0,34!  !value!"
	)
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	echo ╟─────────────────────────────────────────────────────╢

	:: Grace Period
	set "label=Grace Period"
	set "line=║  !label!"
	set "line=!line!!spaces!"
	if %ConfigDeadlineGracePeriod% NEQ -1 (
		if %ConfigDeadlineGracePeriod% == 1 (
			set "value=1 day"
			set "line=!line:~0,45!  !value!"
		) else (
			set "value=%ConfigDeadlineGracePeriod% days"
			if %ConfigDeadlineGracePeriod% LSS 9 (
				set "line=!line:~0,44!  !value!"
			) else (
				set "line=!line:~0,43!  !value!"
			)
		)
	) else (
		set "value=2 days (default)"
		set "line=!line:~0,34!  !value!"
	)
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	echo ╟─────────────────────────────────────────────────────╢

	:: No Auto Reboot
	set "label=Prevent Auto Reboot Until Deadline"
	set "line=║  !label!"
	set "line=!line!!spaces!"
	if %ConfigDeadlineNoAutoReboot% NEQ -1 (
		if %ConfigDeadlineNoAutoReboot% == 1 (
			set "value=True"
			set "line=!line:~0,46!  !value!"
		) else (
			set "value=False"
			set "line=!line:~0,45!  !value!"
		)
	) else (
		set "value=No (default)"
		set "line=!line:~0,38!  !value!"
	)
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	echo ╚═════════════════════════════════════════════════════╝
) else (
	echo         Aggressive update deadlines are DISABLED
)

echo.
echo %dashLine%
echo.

if "%homeEdition%"=="0" (
	echo   1. Automatically Set Max Delays
	echo   2. Manually Configure Delays
) else (
	echo   1. %ESC%[90mAutomatically Set Max Delays%ESC%[0m
	echo   2. %ESC%[90mManually Configure Delays%ESC%[0m
)
echo   3. Remove All Delay Settings
echo   4. Refresh
echo   5. Return To Main Menu
echo.
echo %dashLine%
echo.
set /p "choice=  Enter your choice (1-5): "

if "%choice%"=="1" (
	if "%homeEdition%"=="0" (
		goto set_max_delays
	) else (
		goto set_max_delays_home
	)
)
if "%choice%"=="2" (
	if "%homeEdition%"=="0" (
		goto manual_delay_config
	) else (
		goto manual_delay_config_home
	)
)
if "%choice%"=="3" goto clear_delays
if "%choice%"=="4" goto delay_updates
if "%choice%"=="5" goto menu
goto delay_updates

:: ========== ========== ========== ========== ==========

:set_max_delays

:: Display the title
call :title "Automatic Aggressive Update Settings"

echo Setting aggressive update delays to maximum...

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetComplianceDeadline /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineForFeatureUpdates /t REG_DWORD /d 30 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineForQualityUpdates /t REG_DWORD /d 7 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineGracePeriod /t REG_DWORD /d 7 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineNoAutoReboot /t REG_DWORD /d 1 /f >nul

echo.
echo %dashLine%
echo.

echo Aggressive update delays have been set to maximum.

echo.
pause
goto delay_updates

:: ========== ========== ========== ========== ==========

:set_max_delays_home

call :title "Automatic Aggressive Update Settings"

echo  This feature is not supported on Home editions.
echo.
echo  Windows 10 and 11 Home editions do not honor the
echo  deadline policies. Even if added to the registry,
echo  they will be ignored by the Windows Update system.
echo.
echo  This limitation is hardcoded and cannot be bypassed
echo  without upgrading to Windows Pro or higher.
echo.
echo %dashLine%
echo.

:: Set userInput to an empty string
set "userInput="

:: Prompt for modifying the policies (1/y/yes, 0/n/no)
set /p "userInput=Do you still want to modify these policies? (Y,N): "

:: Remove leading and trailing spaces
set "response=%userInput%"
set "response=!response: =!"

set result=-1
:: Match user input to valid responses
if /i "%response%"=="1" set result=1
if /i "%response%"=="y" set result=1
if /i "%response%"=="yes" set result=1
if /i "%response%"=="0" set result=0
if /i "%response%"=="n" set result=0
if /i "%response%"=="no" set result=0

:: Check if result was set
if "%result%"=="-1" (
	echo Invalid input. Please enter 1/Y/Yes or 0/N/No.
	pause
	goto set_max_delays_home
)
if "%result%"=="0" (
	goto delay_updates
) else (
	:: Result has been accepted
	goto set_max_delays
)

:: ========== ========== ========== ========== ==========

:manual_delay_config

:: Display the title
call :title "Manual Aggressive Update Settings"

if not defined noRebootFlag (
	echo Press Enter to skip any setting and leave it unchanged.
	echo.
)

:: ~~~~~~~~~~

:: Check if featureDays is already set
if defined featureDays (
	echo Feature Update Delay will be set to: %featureDays%
	goto prompt_quality_delay
)

:: Set userInput to an empty string
set "userInput="

:: Prompt for Feature Update delay (0-30 days)
set /p "userInput=Feature Update Delay (0-30 days): "

:: Use a poison to check for nothing
if "!userInput!"=="" (
	if %ConfigDeadlineForFeatureUpdates% == -1 (
		echo The configuration is not set. Default is 2.
		set "featureDays=2"
	) else (
		echo No input provided. Keeping the current setting.
		set "featureDays=%ConfigDeadlineForFeatureUpdates%"
	)
	pause
	goto manual_delay_config
)

:: Set errorlevel to 0
(call )

:: Perform arithmetic
set /a "featureDays=userInput + 0" 2>nul

:: Check for errors
if !errorlevel! NEQ 0 (
	echo Input error. Please try again.
	pause
	set featureDays=
	goto manual_delay_config
)

:: Verify the input matches the evaluated integer
if "%featureDays%" EQU "%userInput%" (
	:: Validate the integer
	if %featureDays% LSS 0 (
		echo Minimum value is 0.
		pause
		set featureDays=
		goto manual_delay_config
	) else if %featureDays% GTR 30 (
		echo Maximum value is 30.
		pause
		set featureDays=
		goto manual_delay_config
	)
) else (
	:: Input was not a valid integer
	echo Invalid input. Please enter a numeric value.
	pause
	set featureDays=
	goto manual_delay_config
)

:: Integer has been accepted
goto manual_delay_config

:: ~~~~~~~~~~

:prompt_quality_delay

:: Check if qualityDays is already set
if defined qualityDays (
	echo Quality Update Delay will be set to: %qualityDays%
	goto prompt_grace_period
)

:: Set userInput to an empty string
set "userInput="

:: Prompt for Quality Update delay (0-30 days)
set /p "userInput=Quality Update Delay (0-30 days): "

:: Use a poison to check for nothing
if "!userInput!"=="" (
	if %ConfigDeadlineForQualityUpdates% == -1 (
		echo The configuration is not set. Default is 2.
		set "qualityDays=2"
	) else (
		echo No input provided. Keeping the current setting.
		set "qualityDays=%ConfigDeadlineForQualityUpdates%"
	)
	pause
	goto manual_delay_config
)

:: Set errorlevel to 0
(call )

:: Perform arithmatic
set /a "qualityDays=userInput + 0" 2>nul

:: Check for errors
if !errorlevel! NEQ 0 (
	echo Input error. Please try again.
	pause
	set qualityDays=
	goto manual_delay_config
)

:: Verify the input matches the evaluated integer
if "%qualityDays%" EQU "%userInput%" (
	:: Validate the integer
	if %qualityDays% LSS 0 (
		echo Minimum value is 0.
		pause
		set qualityDays=
		goto manual_delay_config
	) else if %qualityDays% GTR 30 (
		echo Maximum value is 30.
		pause
		set qualityDays=
		goto manual_delay_config
	)
) else (
	:: Input was not a valid integer
	echo Invalid input. Please enter a numeric value.
	pause
	set qualityDays=
	goto manual_delay_config
)

:: Integer has been accepted
goto manual_delay_config

:: ~~~~~~~~~~

:prompt_grace_period

:: Check if graceDays is already set
if defined graceDays (
	echo Grace Period will be set to: %graceDays%
	goto prompt_no_auto_reboot
)

:: Set userInput to an empty string
set "userInput="

:: Prompt for Grace Period (0-7 days)
set /p "userInput=Grace Period After Deadline (0-7 days): "

:: Use a poison to check for nothing
if "!userInput!"=="" (
	if %ConfigDeadlineGracePeriod% == -1 (
		echo The configuration is not set. Default is 2.
		set "graceDays=2"
	) else (
		echo No input provided. Keeping the current setting.
		set "graceDays=%ConfigDeadlineGracePeriod%"
	)
	pause
	goto manual_delay_config
)

:: Set errorlevel to 0
(call )

:: Perform arithmatic
set /a "graceDays=userInput + 0" 2>nul

:: Check for errors
if !errorlevel! NEQ 0 (
	echo Input error. Please try again.
	pause
	set graceDays=
	goto manual_delay_config
)

:: Verify the input matches the evaluated integer
if "%graceDays%" EQU "%userInput%" (
	:: Validate the integer
	if %graceDays% LSS 0 (
		echo Minimum value is 0.
		pause
		set graceDays=
		goto manual_delay_config
	) else if %graceDays% GTR 7 (
		echo Maximum value is 7.
		pause
		set graceDays=
		goto manual_delay_config
	)
) else (
	:: Input was not a valid integer
	echo Invalid input. Please enter a numeric value.
	pause
	set graceDays=
	goto manual_delay_config
)

:: Integer has been accepted
goto manual_delay_config

:: ~~~~~~~~~~

:prompt_no_auto_reboot

:: Check if noRebootFlag is already set
if defined noRebootFlag (
	echo No Auto Reboot flag will be set to: %noRebootFlag%
	goto delay_config_complete
)

:: Set userInput to an empty string
set "userInput="

:: Prompt for prevent auto rebooting during the grace period (1/y/yes, 0/n/no)
set /p "userInput=Prevent Auto Reboot Until Grace Period Ends? (Y,N): "

if not defined userInput (
	if %ConfigDeadlineNoAutoReboot% == -1 (
		echo The configuration is not set. Default is 0.
		set "noRebootFlag=0"
	) else (
		echo No input provided. Keeping the current setting.
		set "noRebootFlag=%ConfigDeadlineNoAutoReboot%"
	)
	pause
	goto manual_delay_config
)

:: Remove leading and trailing spaces
set "response=%userInput%"
set "response=!response: =!"

:: Match user input to valid responses
if /i "%response%"=="1" set noRebootFlag=1
if /i "%response%"=="y" set noRebootFlag=1
if /i "%response%"=="yes" set noRebootFlag=1
if /i "%response%"=="0" set noRebootFlag=0
if /i "%response%"=="n" set noRebootFlag=0
if /i "%response%"=="no" set noRebootFlag=0

:: Check if noRebootFlag was set
if not defined noRebootFlag (
	echo Invalid input. Please enter 1/Y/Yes or 0/N/No.
	pause
	goto manual_delay_config
)

:: Response has been accepted, write to the registry
goto manual_delay_config

:: ~~~~~~~~~~

:delay_config_complete

:: Always enable SetComplianceDeadline if any values were provided
if defined featureDays (
	goto compliance
) else if defined qualityDays (
	goto compliance
) else if defined graceDays (
	goto compliance
) else if defined noRebootFlag (
	goto compliance
)

goto skip_compliance
:compliance
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetComplianceDeadline /t REG_DWORD /d 1 /f >nul
:skip_compliance

:: Write the settings to the registry
if defined featureDays (
	reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineForFeatureUpdates /t REG_DWORD /d %featureDays% /f >nul
	set featureDays=
)
if defined qualityDays (
	reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineForQualityUpdates /t REG_DWORD /d %qualityDays% /f >nul
	set qualityDays=
)
if defined graceDays (
	reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineGracePeriod /t REG_DWORD /d %graceDays% /f >nul
	set graceDays=
)
if defined noRebootFlag (
	reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ConfigureDeadlineNoAutoReboot /t REG_DWORD /d %noRebootFlag% /f >nul
	set noRebootFlag=
)

echo.
echo %dashLine%
echo.

echo Aggressive update delays have been set.

echo.
pause
goto delay_updates

:: ========== ========== ========== ========== ==========

:manual_delay_config_home

call :title "Manual Aggressive Update Settings"

echo  This feature is not supported on Home editions.
echo.
echo  Windows 10 and 11 Home editions do not honor the
echo  deadline policies. Even if added to the registry,
echo  they will be ignored by the Windows Update system.
echo.
echo  This limitation is hardcoded and cannot be bypassed
echo  without upgrading to Windows Pro or higher.
echo.
echo %dashLine%
echo.

:: Set userInput to an empty string
set "userInput="

:: Prompt for modifying the policies (1/y/yes, 0/n/no)
set /p "userInput=Do you still want to modify these policies? (Y,N): "

:: Remove leading and trailing spaces, and convert to lowercase
set "response=%userInput%"
set "response=!response: =!"

set result=-1
:: Match user input to valid responses
if /i "%response%"=="1" set result=1
if /i "%response%"=="y" set result=1
if /i "%response%"=="yes" set result=1
if /i "%response%"=="0" set result=0
if /i "%response%"=="n" set result=0
if /i "%response%"=="no" set result=0

:: Check if result was set
if "%result%"=="-1" (
	echo Invalid input. Please enter 1/Y/Yes or 0/N/No.
	pause
	goto manual_delay_config_home
)
if "%result%"=="0" (
	goto delay_updates
) else (
	:: Result has been accepted
	goto manual_delay_config
)

:: ========== ========== ========== ========== ==========

:clear_delays

:: Display the title
call :title "Clear Aggressive Update Settings"

echo Clearing aggressive update settings...

for %%V in (SetComplianceDeadline ConfigureDeadlineForFeatureUpdates ConfigureDeadlineForQualityUpdates ConfigureDeadlineGracePeriod ConfigureDeadlineNoAutoReboot) do (
	reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v %%V /f >nul 2>&1
)

echo.
echo %dashLine%
echo.

echo All aggressive update delay settings have been removed.

echo.
pause
goto delay_updates

:: ========== ========== ========== ========== ==========

:required_reboots

:: Display the title
call :title "Required Reboot Operations"

call :check_pending_reboot

set "spaces=                                                   "

echo ╔═════════════════════════════════════════════════════╗

:: Component Based Servicing
set "label=Component Based Servicing"
set "line=║  !label!"
set "line=!line!!spaces!"
if "%CBS%"=="1" (set "value=Yes") else (set "value=No")
set "line=!line:~0,45!  !value!"
set "line=!line!!spaces!"
set "line=!line:~0,53! ║"
echo !line!

if "%CBS%"=="1" (
	echo ║ - - - - - - - - - - - - - - - - - - - - - - - - - - ║

	set "detail=• servicing changes pending"
	set "line=║      !detail!"
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	set "detail=• reboot will complete component servicing"
	set "line=║      !detail!"
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!
)

echo ╟─────────────────────────────────────────────────────╢

:: Windows Update Reboot Required
set "label=Windows Update"
set "line=║  !label!"
set "line=!line!!spaces!"
if "%WU%"=="1" (set "value=Yes") else (set "value=No")
set "line=!line:~0,45!  !value!"
set "line=!line!!spaces!"
set "line=!line:~0,53! ║"
echo !line!

if "%WU%"=="1" (
	echo ║ - - - - - - - - - - - - - - - - - - - - - - - - - - ║

	set "detail=• updates have been staged"
	set "line=║      !detail!"
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	set "detail=• reboot required to finish installation"
	set "line=║      !detail!"
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!
)

echo ╟─────────────────────────────────────────────────────╢

:: Pending FileRenameOperations
set "label=Pending FileRenameOperations"
set "line=║  !label!"
set "line=!line!!spaces!"
if "%PFR%"=="1" (set "value=Yes") else (set "value=No")
set "line=!line:~0,45!  !value!"
set "line=!line!!spaces!"
set "line=!line:~0,53! ║"
echo !line!

if "%PFR%"=="1" (
	echo ║ - - - - - - - - - - - - - - - - - - - - - - - - - - ║

	set "detail=• files marked for rename/deletion"
	set "line=║      !detail!"
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!

	set "detail=• reboot needed to apply changes"
	set "line=║      !detail!"
	set "line=!line!!spaces!"
	set "line=!line:~0,53! ║"
	echo !line!
)

echo ╚═════════════════════════════════════════════════════╝

echo.
if "%REBOOT_PENDING%"=="1" (
	echo                 A reboot is required
	echo.
) else (
	echo            System is in a clean reboot state
	echo          No pending reboot operations detected
)

echo %dashLine%
echo.

pause
goto menu

:: ========== ========== ========== ========== ==========

:end

if "%silent%"=="false" (
	cls
	echo.
	echo.
	echo %ESC%[90m=======================================================%ESC%[0m
	echo.
	echo.
	echo        Thank you for using Always Active Hours.
	echo.
	echo.
	echo %ESC%[90m=======================================================%ESC%[0m
	echo.
	echo.

	title Command Prompt
)

:: End the local environment and preserve key values
endlocal & (
	set "EXIT_CODE=%EXIT_CODE%"
)

if defined codepage chcp %codepage% >nul

exit /b %EXIT_CODE%

:: ========== ========== ========== ========== ==========

:: Use multi-byte characters to offset the Command Prompt parsing buffer,
:: causing the subsequent line to either parse as flag or as a failed command
:: used to verify line endings and repair the file if necessary
::
:: Buffer blocks are used to clear the Command Prompt's parsing buffer

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:eol_verify_dbcs
rem ══
:═?    ?

if %errorlevel% EQU 9009 ( cls & goto repair )
goto main

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:eol_verify
rem ═
:═?    ?

if %errorlevel% EQU 9009 ( cls & goto repair )
goto main

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:repair

:: Prevent recursive repair
if defined EOL_REPAIRED goto main
set "EOL_REPAIRED=1"

:: Source and temp paths
set "src=%~f0" & set "tmp=%TEMP%\%~nx0_%random%.tmp"

:: Normalize LF to CRLF into the temp file
type "%src%" | find /V "" > "%tmp%"

:: Copy the temp file to our original source, remove the temp file, reset the code page and restart
type "%tmp%" > "%src%" & del "%tmp%" & chcp "%codepage%" >nul & call "%src%" %* & exit /b 0
