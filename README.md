Fuck You Microsoft
========
Because I've set everything up 30 times and the computer still automatically resets. Fuck you.

Overview
------------
"Always Active Hours.bat" is a self-contained batch script designed to manage and adjust your Windows Active Hours. By shifting the active hours based on the current time, the tool helps prevent Windows from automatically restarting your PC to complete updates, reducing the risk of unexpected reboots during use.

The script autonomously installs itself when enabling its scheduled task, runs periodic adjustments as needed, and removes itself cleanly when the scheduled task is disabled. It operates without external dependencies, relying solely on built-in Windows commands and registry modifications.

Windows typically enforces an 18-hour active window, but this script keeps you perpetually in the middle of that period. The script is designed to have Windows restart your PC only during inactive hours. If Windows automatically manages your active hours, you lose control over restart timing. Even if you manually set your active hours and enforce a no-reboot policy, the computer should reboot only when it's inactive. However, this raises a question: what happens if the system is always within the defined active hours, especially given Windows' restrictions?

How It Works
------------

*Execution Modes*

**Interactive Mode:**  
When run manually, the script presents a menu for configuring settings such as enabling/disabling the scheduled task, toggling reboot policies, or shifting active hours manually.

**Scheduled Task Mode:**  
When invoked with the `/task` parameter (by the scheduled task), the script shifts active hours automatically without user interaction.

Installation & Removal:
=======================

**Enabling the Task:**  
Initiating the scheduled task triggers the script to copy itself to a designated location (`%ProgramData%\Always Active Hours`) and schedule periodic execution.

**Disabling the Task:**  
Removing the scheduled task invokes the uninstallation routine, which deletes the script file and cleans up its directory if empty.

Active Hours Adjustment:
------------------------

- The script reads the current active hours from the registry.
- It calculates new active hours based on the current time to create an 18-hour active window centered around the current time.
- The new settings are written back to the registry, preventing Windows from restarting during these hours.
