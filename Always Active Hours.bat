@echo off

:: Set code page to UTF-8
CHCP 65001 >nul

setlocal enabledelayedexpansion
title Always Active Hours Configurator

:: ========== ========== ========== ========== ==========

ver | findstr /r "10\.0\.[0-9]*" >nul || (
	echo ERROR: Unsupported Windows version.
	exit /b
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

if "%asAdministrator%"=="false" (
	if "%asTask%"=="true" (
		exit /b
	) else (
		echo This script must be run as an administrator.
		echo Right-click the script and select "Run as Administrator."
		pause
		exit /b
	)
)

:: ==========

if "%asTask%"=="true" (
	goto shift_hours
)

:: ==========

set "taskName=Always Active Hours"
set "scriptPath=%~f0"
set "xmlPath=%temp%\AlwaysActiveHours.xml"

goto menu

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

:: ==========

:menu_display

cls
echo =======================================================
echo            Always Active Hours Configurator
echo =======================================================
echo.

echo ^[[32mWelcome to Always Active Hours Configurator^[[0m

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

:: Generate the bar (23 blocks)
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

:: Generate hour labels (every 3 hours for spacing)
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

:: Display the bar and labels
echo !arrow!
echo !bar!
echo !labels!
endlocal
goto :eof

:: ========== ========== ========== ========== ==========

:toggle_task

echo.
echo ----------
echo.

if "%taskExists%"=="true" (
	:: Remove the scheduled task
	echo Removing the scheduled task...
	schtasks /delete /tn "%taskName%" /f >nul 2>&1
	set "taskState=remove"
) else (
	:: Add the scheduled task using XML
	echo Adding the scheduled task...

	REM Create temporary XML file
	(
		echo ^<?xml version="1.0" encoding="UTF-16"?^>
		echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
		echo   ^<RegistrationInfo^>
		echo     ^<Date^>%date%T%time:~0,8%^</Date^>
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
		echo       ^<StartBoundary^>%date%T00:00:00^</StartBoundary^>
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
		echo       ^<Command^>"%scriptPath%"^</Command^>
		echo       ^<Arguments^>/task^</Arguments^>
		echo     ^</Exec^>
		echo   ^</Actions^>
		echo ^</Task^>
	) > "%xmlPath%"

	:: Register the task using the XML file
	schtasks /create /tn "%taskName%" /xml "%xmlPath%" /ru SYSTEM /f >nul 2>&1

	:: Clean up the XML file
	del "%xmlPath%" >nul 2>&1

	set "taskState=create"
)

goto task_check
:task_check
	schtasks /query /tn "%taskName%" >nul 2>&1
	if "%taskState%"=="remove" (
		if %errorlevel% equ 0 (
			echo Error: Failed to remove the scheduled task '%taskName%'.
		) else (
			echo Scheduled task '%taskName%' removed successfully.
		)
	) else (
		if %errorlevel% equ 0 (
			echo Scheduled task '%taskName%' created successfully.
		) else (
			echo Error: Failed to create the scheduled task '%taskName%'.
		)
	)

echo.
echo ----------
echo.
pause
goto menu

:: ========== ========== ========== ========== ==========

:toggle_no_reboot

echo.
echo ----------
echo.

if "%noRebootPolicy%"=="true" (
	:: Disable No Auto Reboot Policy
	echo Attempting to delete No Auto Reboot policy...
	reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /f >c:\_windows\debug.txt 2>&1

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
	reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f >c:\_windows\debug.txt 2>&1

	set "result="
	for /f "tokens=*" %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers 2^>nul') do set "result=%%A"

	if defined result (
		echo No Auto Reboot policy has been enabled successfully.
	) else (
		echo Error: Failed to enable No Auto Reboot policy.
	)
)

echo.
echo ----------
echo.
pause
goto menu

:: ========== ========== ========== ========== ==========

:shift_hours

echo.
echo ----------
echo.

:: Calculate and shift active hours

:: Get current hour using WMIC (24-hour format)
for /F "tokens=2 delims==" %%H in ('wmic path win32_localtime get hour /value') do set currentHour=%%H

:: Ensure currentHour is numeric
set /A currentHour=%currentHour%+0
if "%currentHour%"=="" set currentHour=0

:: Calculate startHour
set /A startHour=(currentHour - 9)
if %startHour% LSS 0 set /A startHour+=24

:: Calculate endHour
set /A endHour=(currentHour + 9) %% 24

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
echo ----------
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