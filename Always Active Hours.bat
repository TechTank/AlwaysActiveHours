@echo off
REM Version: 1.0
REM Filename: Always Active Hours.bat
REM Written by: Brogan Scott Houston McIntyre

:: Set column and row dimensions
mode con: cols=55 lines=30

:: Set code page to UTF-8
CHCP 65001 >nul

setlocal enabledelayedexpansion
title Always Active Hours Configurator

:: ========== ========== ========== ========== ==========

ver | findstr /r "10\.0\.[0-9]*" >nul || (
	echo Error: Unsupported Windows version.
	pause
	goto end
)

:: ========== ========== ========== ========== ==========

:: Check for administrator privileges
NET SESSION >nul 2>&1
if %errorlevel% neq 0 (
	set "asAdministrator=false"
) else (
	set "asAdministrator=true"
)

:: Detect if running as a scheduled task using a command-line argument
if "%~1"=="/task" (
	set "asTask=true"
) else (
	set "asTask=false"
)

:: ==========

:: Reject non-administrators
if "%asAdministrator%"=="false" (
	if "%asTask%"=="true" (
		goto end
	) else (
		echo Error: This script must be run as an administrator.
		echo Right-click the script and select "Run as Administrator."
		pause
		goto end
	)
)

:: ==========

if "%asTask%"=="true" (
	goto shift_hours
)

:: ==========

:: Set task variables
set "taskName=Always Active Hours"
set "scriptPath=%~f0"
set "xmlPath=%temp%\AlwaysActiveHours.xml"
set "targetDir=%ProgramData%\AlwaysActiveHours"
set "taskErrorLog=%temp%\schtasks_error.log"

goto menu

:: ========== ========== ========== ========== ==========

:get_active_hours_range

:: Fetch Active Hours Max Range if set by policy
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ActiveHoursMaxRange >nul 2>&1
if %errorlevel% equ 0 (
	for /f "tokens=3" %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ActiveHoursMaxRange 2^>nul') do set activeHoursMaxRange=%%A
) else (
	set activeHoursMaxRange=0x12
)
set /a activeHoursMaxRangeDec=%activeHoursMaxRange%

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

:menu

:: Check if the scheduled task exists
schtasks /query /tn "%taskName%" >nul 2>&1
if %errorlevel% equ 0 (
	set taskExists=true
) else (
	set taskExists=false
)

:: Fetch current active hours from the registry
for /f "tokens=3" %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursStart 2^>nul') do set activeStart=%%A
for /f "tokens=3" %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursEnd 2^>nul') do set activeEnd=%%A

:: Convert active hours to AM/PM format
call :convert_to_ampm %activeStart% activeStartDisplay
call :convert_to_ampm %activeEnd% activeEndDisplay

:: Fetch No Auto Reboot configuration
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers >nul 2>&1
if %errorlevel% equ 0 (
	set noRebootPolicy=true
) else (
	set noRebootPolicy=false
)

:: Resolve the effective active hours range (policy or default)
call :get_active_hours_range

:: ==========

:menu_display

:: Reset choice variable
set "choice="

:: Display the menu
cls
echo ╔═════════════════════════════════════════════════════╗
echo ║          Always Active Hours Configurator           ║
echo ╚═════════════════════════════════════════════════════╝
echo.

if defined activeStartDisplay if defined activeEndDisplay (
	call :display_active_hours %activeStart% %activeEnd%
	echo.
	set "space="
	if %activeStart% LSS 10 if %activeEnd% LSS 10 set "space= "
	if %activeStart% GEQ 12 if %activeStart% LEQ 21 set "space= "
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
echo -------------------------------------------------------
echo.
if "%taskExists%"=="true" (
	echo   1. Disable Scheduled Task
) else (
	echo   1. Enable Scheduled Task
)
if "%noRebootPolicy%"=="true" (
	echo   2. Disable No Auto Reboot Policy
) else (
	echo   2. Enable No Auto Reboot Policy
)
echo   3. Shift Active Hours
echo   4. Refresh
echo   5. Exit
echo.
echo -------------------------------------------------------
echo.
set /p choice="  Enter your choice (1-5): "

if '%choice%' == '1' goto toggle_task
if '%choice%' == '2' goto toggle_no_reboot
if '%choice%' == '3' goto shift_hours
if '%choice%' == '4' goto menu
if '%choice%' == '5' goto end
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

:: Get the current hour
for /f "tokens=2 delims==" %%H in ('wmic path win32_localtime get hour /value') do set currentHour=%%H

:: Normalize end hour for wrap-around
if %end% LSS %start% (
	set /a normalized_end=%end%+24
) else (
	set /a normalized_end=%end%
)

:: Generate the bar and arrow lines
for /l %%H in (0,1,23) do (
	set /a hour=%%H
	set /a normalized_hour=hour
	if !hour! LSS %start% set /a normalized_hour=hour+24

	if %%H EQU %currentHour% (
		if !normalized_hour! GEQ %start% if !normalized_hour! LSS %normalized_end% (
			set "block=█"  :: Active current hour
		) else (
			set "block=▒"  :: Inactive current hour
		)
		set "arrow=!arrow! ↓"
	) else (
		if !normalized_hour! GEQ %start% if !normalized_hour! LSS %normalized_end% (
			set "block=▓"  :: Active hours
		) else (
			set "block=░"  :: Inactive hours
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

:toggle_task

echo.
echo .......................................................
echo.

if "%taskExists%"=="true" (
	:: Remove the scheduled task
	echo Removing the scheduled task...
	schtasks /delete /tn "%taskName%" /f >nul 2>&1

	call :uninstall

	:: Set the task action
	set "taskAction=remove"
	goto task_check
)

:: Detect date format by checking the position of the year
for /f "tokens=1-3 delims=/- " %%A in ("%DATE%") do (
	if %%A GTR 31 (
		set yyyy=%%A
		set mm=%%B
		set dd=%%C
	) else if %%C GTR 31 (
		set yyyy=%%C
		set mm=%%A
		set dd=%%B
	) else (
		set yyyy=20%%C
		set mm=%%A
		set dd=%%B
	)
)

:: Get time components
set hh=%TIME:~0,2%
set min=%TIME:~3,2%
set ss=%TIME:~6,2%

:: Trim leading space for single-digit hours
setlocal enabledelayedexpansion
set hh=!hh: =!
if !hh! LSS 10 set hh=0!hh!
endlocal & set hh=%hh%

:: Format the date-time as YYYY-MM-DDTHH:mm:ss
set formattedDate=%yyyy%-%mm%-%dd%T%hh%:%min%:%ss%

:: Add the scheduled task using XML
echo Adding the scheduled task...

call :install

:: Ensure SmartActiveHoursState is set to 0
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v SmartActiveHoursState /t REG_DWORD /d 0 /f >nul
if %errorlevel% neq 0 (
	echo Error: Failed to set SmartActiveHoursState to 0.
	echo.
	echo -------------------------------------------------------
	echo.
	pause
	goto menu
)

REM Create temporary XML file
(
	echo ^<?xml version="1.0" encoding="UTF-16"?^>
	echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
	echo   ^<RegistrationInfo^>
	echo     ^<Date^>%formattedDate%^</Date^>
	echo     ^<Author^>%username%^</Author^>
	echo     ^<URI^\>%taskName%^</URI^>
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
	echo       ^<StartBoundary^>%yyyy%-%mm%-%dd%T00:00:00^</StartBoundary^>
	echo       ^<Enabled^>true^</Enabled^>
	echo       ^<ScheduleByDay^>
	echo         ^<DaysInterval^>1^</DaysInterval^>
	echo       ^</ScheduleByDay^>
	echo     ^</CalendarTrigger^>
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
	echo     ^<ExecutionTimeLimit^>PT15S^</ExecutionTimeLimit^>
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
	echo XML file "%xmlPath%" does not exist.
	echo Unable to create the scheduled task without the XML configuration.
	echo.
	echo -------------------------------------------------------
	echo.
	pause
	goto menu
)

:: Register the task using the XML file
schtasks /create /tn "%taskName%" /xml "%xmlPath%" /ru SYSTEM /f >"%taskErrorLog%" 2>&1

:: Clean up the XML file
del "%xmlPath%" >nul 2>&1

:: Set the task action
set "taskAction=create"

goto task_check
:task_check

	:: Check if the task action was sucessful or not
	schtasks /query /tn "%taskName%" >nul 2>&1
	if "%taskAction%"=="remove" (
		if %errorlevel% equ 0 (
			echo Error: Failed to remove the scheduled task.
		) else (
			echo Scheduled task removed successfully.
		)
	) else (
		if %errorlevel% equ 0 (
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

echo.
echo -------------------------------------------------------
echo.
pause
goto menu

:: ==========

:install

:: Check if already installed in target location
if /I "%~dp0"=="%targetDir%\" (
	if /I "%~nx0"=="Always Active Hours.bat" (
		goto :eof
	)
)

:: Create target directory if it doesn't exist
if not exist "%targetDir%" (
	mkdir "%targetDir%"
)

:: Copy script to ProgramData directory
xcopy "%scriptPath%" "%targetDir%\Always Active Hours.bat" /Y /-I /Q >nul 2>&1

goto :eof

:: ==========

:uninstall

:: Delete the script file if it exists in the target directory
if exist "%targetDir%\Always Active Hours.bat" (
	del "%targetDir%\Always Active Hours.bat" /F /Q
)

:: Check if the directory is empty
dir /b "%targetDir%" | findstr . >nul
if errorlevel 1 (
	:: Directory is empty; attempt to remove it
	rd "%targetDir%"
)

goto :eof

:: ========== ========== ========== ========== ==========

:toggle_no_reboot

echo.
echo .......................................................
echo.

if "%noRebootPolicy%"=="true" (
	:: Disable No Auto Reboot Policy
	echo Attempting to delete No Auto Reboot policy...
	reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /f >nul 2>&1

	set "result="
	for /f "tokens=*" %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers 2^>nul') do set "result=%%A"

	if not defined result (
		echo No Auto Reboot policy has been disabled successfully.
	) else (
		echo Error: Failed to disable No Auto Reboot policy.
	)
) else (
	:: Enable No Auto Reboot Policy
	echo Attempting to add No Auto Reboot policy...
	reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f >nul 2>&1

	set "result="
	for /f "tokens=*" %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers 2^>nul') do set "result=%%A"

	if defined result (
		echo No Auto Reboot policy has been enabled successfully.
	) else (
		echo Error: Failed to enable No Auto Reboot policy.
	)
)

echo.
echo -------------------------------------------------------
echo.
pause
goto menu

:: ========== ========== ========== ========== ==========

:shift_hours

echo.
echo .......................................................
echo.

:: Calculate and shift active hours

:: Get current hour using WMIC (24-hour format)
for /F "tokens=2 delims==" %%H in ('wmic path win32_localtime get hour /value') do set currentHour=%%H

:: Ensure currentHour is numeric
set /A currentHour=%currentHour%+0
if "%currentHour%"=="" set currentHour=0

:: Resolve the effective active hours range (policy or default)
call :get_active_hours_range

:: Calculate half-range (floor/ceil for odd numbers)
set /a halfLow=activeHoursMaxRangeDec / 2
set /a halfHigh=activeHoursMaxRangeDec - halfLow

:: Calculate start hour
set /a startHour=(currentHour - halfLow)
if %startHour% LSS 0 set /a startHour+=24

:: Calculate end hour
set /a endHour=(currentHour + halfHigh) %% 24

:: Write registry values
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursStart /t REG_DWORD /d %startHour% /f >nul
if %errorlevel% equ 0 (
	echo ActiveHoursStart set to %startHour%
) else (
	echo Error: Failed to set ActiveHoursStart. ErrorLevel: %errorlevel%
)

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursEnd /t REG_DWORD /d %endHour% /f >nul
if %errorlevel% equ 0 (
	echo ActiveHoursEnd set to %endHour%
) else (
	echo Error: Failed to set ActiveHoursEnd. ErrorLevel: %errorlevel%
)

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v UserChoiceActiveHoursStart /t REG_DWORD /d %startHour% /f >nul
if %errorlevel% equ 0 (
	echo UserChoiceActiveHoursStart set to %startHour%
) else (
	echo Error: Failed to set UserChoiceActiveHoursStart. ErrorLevel: %errorlevel%
)

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v UserChoiceActiveHoursEnd /t REG_DWORD /d %endHour% /f >nul
if %errorlevel% equ 0 (
	echo UserChoiceActiveHoursEnd set to %endHour%
) else (
	echo Error: Failed to set UserChoiceActiveHoursEnd. ErrorLevel: %errorlevel%
)

:: End if running as a task
if "%asTask%"=="true" (
	goto end
)

:: Convert startHour and endHour to AM/PM format
call :convert_to_ampm %startHour% newStartDisplay
call :convert_to_ampm %endHour% newEndDisplay

echo.
echo -------------------------------------------------------
echo.

:: Display updated active hours
echo Active hours shifted to %newStartDisplay% - %newEndDisplay%.

echo.
pause
goto menu

:: ========== ========== ========== ========== ==========

:end
endlocal
exit /b