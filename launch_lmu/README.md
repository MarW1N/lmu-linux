# Description
I made this launch_lmu.sh to make it easier for myself to launch LMU so that I can use TinyPedal (https://github.com/TinyPedal/TinyPedal) using the native LMU API with the help of *lmushm* and *lmubridge.exe* from https://github.com/Spacefreak18/simshmbridge and thought someone else might find it useful.

Then I found the excellent LMUFFB (https://github.com/coasting-nc/LMUFFB) to make use of LMU telemetry to enhance the force feedback and incorporated that as well, along with automatic startup and shutdown orchestration for CrewChief (https://gitlab.com/mr_belowski/CrewChiefV4).

## Configuration

### lmushm and lmubridge.exe
Uncomment `LMUSHM_BIN` and `LMUBRIDGE_BIN` in `launch_lmu.env` and make sure they point to your `lmushm` and `lmubridge.exe` binaries.

### LMUFFB
Uncomment `LMUFFB_BIN` in `launch_lmu.env` and make sure it points to the `LMUFFB.exe` binary.

### CrewChief
Uncomment `CREWCHIEF_BIN` in `launch_lmu.env` and make sure it points to `CrewChiefV4.exe`. When enabled, `launch_lmu.sh` automatically ensures `.userSettings.use_naudio = false` in CrewChief's profiles so audio does not hang under Wine/Proton.

### Startup Delays and GameMode
Helper tools start at configurable offsets (in seconds) after `Le Mans Ultimate.exe` launches: `LMUBRIDGE_DELAY=10`, `LMUFFB_DELAY=15`, and `CREWCHIEF_DELAY=35` (with `CREWCHIEF_STARTUP_TIMEOUT=30`). GameMode (`gamemoderun`) is used automatically when installed and can be toggled with `USE_GAMEMODE=true|false`.

### Shared Memory Plugin (`CustomPluginVariables.JSON`)
`CONFIGURE_SHARED_MEMORY_PLUGIN=true` (enabled by default in `launch_lmu.env`) automatically configures `UserData/player/CustomPluginVariables.JSON` so that `rFactor2SharedMemoryMapPlugin64_Wine.dll` and `ChatTransceiver.dll` are enabled and `LMU.3.8.SharedMemoryMapPlugin.dll` (which fails under Wine) is disabled. Set `CONFIGURE_SHARED_MEMORY_PLUGIN=false` to manage `CustomPluginVariables.JSON` manually.

### Logging and Desktop Notifications
Launcher, game, and helper-process output is written to `logs/launch_lmu.log` (with per-helper logs in `logs/lmushm.log`, `logs/lmubridge.log`, `logs/lmuffb.log`, and `logs/crewchief.log`). The active logs and up to nine uncompressed, numbered archives (for example, `launch_lmu.log.1`) are kept in the `logs` folder.

Desktop notifications (`notify-send`) are displayed when the game and helper tools start and stop, and critical notifications (`notify-send -u critical`) are shown alongside `ERROR:` log entries whenever a configuration or runtime error prevents normal operation.

Debug logging can be activated by uncommenting `DEBUG=true` in `launch_lmu.env`.

## Invocation of script
- In Steam launch options for Le Mans Ultimate `/some/path/launch_lmu.sh %command%`
- Launch Le Mans Ultimate and have some fun

