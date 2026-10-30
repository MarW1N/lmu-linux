# Description
I made this `launch_lmu.sh` script to make it easier to launch Le Mans Ultimate (LMU) on Linux alongside helper tools:
- **lmushm** and **lmubridge.exe** from [simshmbridge](https://github.com/Spacefreak18/simshmbridge) so tools like [TinyPedal](https://github.com/TinyPedal/TinyPedal) can read native LMU shared memory telemetry.
- **LMUFFB** ([coasting-nc/LMUFFB](https://github.com/coasting-nc/LMUFFB)) to enhance force feedback using LMU telemetry.
- **CrewChief** ([CrewChiefV4](https://gitlab.com/mr_belowski/CrewChiefV4)) with automatic startup, Wine/Proton audio & shared-memory profile fixes, and clean shutdown orchestration.

## Requirements
- `jq`, `pgrep`, and `pkill` (required)
- `protontricks-launch` (required when `CREWCHIEF_BIN` is enabled)
- `rFactor2SharedMemoryMapPlugin64_Wine.dll` installed in LMU's `Plugins/` directory (required when `CONFIGURE_SHARED_MEMORY_PLUGIN=true`)
- `gamemoderun` (optional, used when `USE_GAMEMODE=true`)
- `notify-send` (optional, used for desktop notifications)

## Installation
Run `make install` (from either the repository root or `launch_lmu/`) to install `launch_lmu.sh`, `README.md`, and `launch_lmu.env` into `~/Apps/launch_lmu` (override with `make install APP_DIR=/custom/path`). If `launch_lmu.env` already exists in the target directory, it is preserved.

## Configuration

### lmushm and lmubridge.exe
Uncomment `LMUSHM_BIN` and `LMUBRIDGE_BIN` in `launch_lmu.env` and make sure they point to your `lmushm` and `lmubridge.exe` binaries.

### LMUFFB
Uncomment `LMUFFB_BIN` in `launch_lmu.env` and make sure it points to the `LMUFFB.exe` binary.

### CrewChief
Uncomment `CREWCHIEF_BIN` in `launch_lmu.env` and make sure it points to `CrewChiefV4.exe`. When enabled, `launch_lmu.sh` automatically updates CrewChief's profiles in the LMU Proton prefix so that `.userSettings.use_naudio = false` (preventing Wine/Proton audio hangs) and aligns the legacy rF2 shared memory settings when `CONFIGURE_SHARED_MEMORY_PLUGIN=true`.

Proton's `xalia.exe` gamepad UI helper is also disabled by default (`PROTON_USE_XALIA=0`), preventing severe wineserver/COM accessibility polling storms against WinForms apps like CrewChief.

### Startup Delays and GameMode
Helper tools start at configurable offsets (in seconds) after `Le Mans Ultimate.exe` launches: `LMUBRIDGE_DELAY=10`, `LMUFFB_DELAY=15`, and `CREWCHIEF_DELAY=35` (with `CREWCHIEF_STARTUP_TIMEOUT=30`). GameMode (`gamemoderun`) is used automatically when installed and can be toggled with `USE_GAMEMODE=true|false`.

### Shared Memory Plugin (`CustomPluginVariables.JSON`)
`CONFIGURE_SHARED_MEMORY_PLUGIN=true` (enabled by default) automatically configures `UserData/player/CustomPluginVariables.JSON` so that `rFactor2SharedMemoryMapPlugin64_Wine.dll` and `ChatTransceiver.dll` are enabled and `LMU.3.8.SharedMemoryMapPlugin.dll` (which fails under Wine) is disabled. Set `CONFIGURE_SHARED_MEMORY_PLUGIN=false` to manage `CustomPluginVariables.JSON` manually.

### Quick Chat Overrides (`Settings.JSON`)
Uncomment and customize `QUICK_CHAT_1` through `QUICK_CHAT_12` in `launch_lmu.env` to automatically update the quick chat messages in `UserData/player/Settings.JSON` on launch. Leave them commented out or blank to keep your existing in-game quick chat settings untouched.

### Logging and Desktop Notifications
Launcher, game, and helper-process output is written to `logs/launch_lmu.log` (with per-helper logs in `logs/lmushm.log`, `logs/lmubridge.log`, `logs/lmuffb.log`, and `logs/crewchief.log`). The active logs and up to nine uncompressed, numbered archives (for example, `launch_lmu.log.1`) are kept in the `logs` folder.

Desktop notifications (`notify-send`) are displayed when the game and helper tools start and stop, and critical notifications (`notify-send -u critical`) are shown alongside `ERROR:` log entries whenever a configuration or runtime error prevents normal operation.

Debug logging can be activated by uncommenting `DEBUG=true` in `launch_lmu.env`.

## Validating Configuration (`--check`) and Development
- Run `./launch_lmu.sh --check` to validate `launch_lmu.env`, required commands, and configured helper executable paths without rotating logs, modifying game/helper JSON files, or launching the game.
- For script development, run `make check` to verify formatting (`shfmt -d`), static analysis (`shellcheck`), and syntax (`bash -n`), or `make fmt` to format `launch_lmu.sh` in place.

## Invocation of script
- In Steam launch options for Le Mans Ultimate: `/path/to/launch_lmu.sh %command%`
- Launch Le Mans Ultimate and have some fun!

