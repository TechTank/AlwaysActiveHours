<p align="center">
  <img src="https://github.com/user-attachments/assets/07f95c28-ddda-483d-90f1-4b17dc89133a" alt="logo">
</p>

## Overview

**Always Active Hours.bat** is a self-contained Windows batch script that manages and continually adjusts your **Windows Active Hours** and related update behaviour. Its goal is simple:
<br>
<p align="center">
<strong>Reduce the chance of Windows Update restarting your PC while you are actively using it.</strong>
</p>
<br>

The script:

- Keeps your system safely inside Windows’ allowed **Active Hours** window.
- Shifts Active Hours as time passes so you remain near the **middle** of the allowed span.
- Sets and maintains update/restart policies via the Registry and Task Scheduler.
- Offers optional controls for update deadlines and restart behaviour on supported editions of Windows.
- Installs and removes itself cleanly with no external dependencies.
<br>
Everything is implemented in a single `.bat` file using built-in Windows commands and registry edits.

No services, no extra executables, no third-party tools.

<br>

## How It Works

### Execution Modes

<br>

**Interactive Mode:**

When run manually, the script displays an interactive console menu that allows you to:

- Enable or disable the scheduled task
- Shift Active Hours immediately
- Toggle reboot protection policies
- Configure or clear aggressive update delays
- View pending reboot conditions

<br>

**Scheduled Task Mode:**

When run with the `/task` parameter (used by the scheduled task), the script operates silently and automatically shifts active hours without any user interaction.

<br>

**Command Line Switches:**
```
Always Active Hours.bat                  :: Interactive menu (default)
Always Active Hours.bat /install         :: Install script + scheduled task, then exit
Always Active Hours.bat /enable          :: Alias for /install

Always Active Hours.bat /uninstall       :: Remove scheduled task + installed copy
Always Active Hours.bat /disable         :: Alias for /uninstall

Always Active Hours.bat /task            :: Scheduled task mode (silent, no UI)
Always Active Hours.bat /q               :: Quiet mode; shift Active Hours, then exit
Always Active Hours.bat /quiet           :: Alias for /q
```

<br>

## Installation & Removal

### Enabling the Task

When enabled, the script:

1. Copies itself to: `%ProgramData%\AlwaysActiveHours\Always Active Hours.bat`
2. Assigns secure SYSTEM-level permissions to the installation directory.
3. Creates a hidden scheduled task that runs:
  - At system startup
  - Once per hour
  - On specific power-related system events

From this point on, Active Hours are maintained automatically in the background.

---

### Disabling the Task

When disabled, the script:

- Removes the scheduled task
- Deletes the installed copy of the script
- Removes the installation directory if it is empty
- Restores any temporary permission changes

No files are left behind.

<br>

## Active Hours Adjustment

Each automatic or manual shift performs the following steps:

- Reads the current Active Hours values from the registry.
- Reads the system’s configured Active Hours maximum range.
- Calculates a new range centred around the current system time.
- Writes the following values back to the registry:
  - `ActiveHoursStart`
  - `ActiveHoursEnd`
  - `UserChoiceActiveHoursStart`
  - `UserChoiceActiveHoursEnd`
- Forces `SmartActiveHoursState = 0` to prevent Windows from overriding the values automatically.

The result is a continuously sliding Active Hours window that keeps your active time safely inside the allowed reboot-free period.

<br>

## System Requirements

- Windows 10 or Windows 11
- Administrator privileges are required for:
- Task Scheduler access
- Registry modification
- Installation under `%ProgramData%`

> Note: On domain-managed or heavily policy-restricted systems, Group Policy may override some settings.

<br>

## Transparency & Safety

- No background services are installed.
- No network access is used.
- All configuration changes are limited to documented Windows Update and Active Hours registry keys.
- The entire script is plain text and fully auditable.
- A built-in self-repair routine automatically corrects line-ending corruption if the file is edited incorrectly.

<br>

## Author

Created by [Brogan Scott Houston McIntyre (TechTank)](https://github.com/TechTank)
