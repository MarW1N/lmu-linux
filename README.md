launch_lmu.sh is a script that helps launch LMU together with lmushm and lmubridge.exe from https://github.com/Spacefreak18/simshmbridge

The script should be invoked using Steam Launch Options as below

/some/path/launch_lmu.sh %command%

Debug logging can be activated by adding "DEBUG=true" (without ") on a separate line in launch_lmu.env. This will create launch_lmu.log in the same folder as the script. Below is example output from starting and stopping LMU.

```
<launching game in Steam here>
[16:57:50] lmubridge.exe path: /home/user/Apps/simshmbridge/bin/lmubridge.exe
[16:57:50] lmushm path: /home/user/Apps/simshmbridge/bin/lmushm
[16:57:50] Using Proton executable at: /home/user/.local/share/Steam/compatibilitytools.d/GE-Proton10-34-LMU-hid_fixes/proton
[16:57:51] Starting lmushm...
[16:57:51] Starting Le Mans Ultimate...
[16:57:51] Using gamemoderun: /usr/games/gamemoderun
[16:58:01] Le Mans Ultimate.exe is still running...
[16:58:01] lmubridge.exe is still running.
[16:58:01] lmushm is still running.
<stopping game here>
[16:58:32] Game stopped! Closing lmubridge.exe...
[16:58:32] Process lmubridge.exe running, attempting to kill...
[16:58:33] Process killed: lmubridge.exe
[16:58:33] Process lmushm is running, attempting to kill...
[16:58:33] Process killed: lmushm
```
