#!/usr/bin/env bash
set -euo pipefail

# Save Steam's LD_PRELOAD and clear it so helper commands don't emit ELFCLASS32 warnings
STEAM_LD_PRELOAD="${LD_PRELOAD-}"
unset LD_PRELOAD

# Launch LMU from Steam with these launch options:
# /path/to/launch_lmu.sh %command%

# Get the path to the directory containing this script
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Keep the active logs and numbered archives together under logs/.
LOG_DIR="${SCRIPT_PATH}/logs"
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/launch_lmu.log"

rotate_log() {
    local log_file="$1"

    rm -f -- "${log_file}.9"
    for ((i = 8; i >= 1; i--)); do
        if [[ -e "${log_file}.${i}" ]]; then
            mv -- "${log_file}.${i}" "${log_file}.$((i + 1))"
        fi
    done
    if [[ -e "$log_file" ]]; then
        mv -- "$log_file" "${log_file}.1"
    fi
}

# Start a fresh main log and capture all launcher output while keeping it visible
rotate_log "$LOG_FILE"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "####### BEGIN LAUNCH_LMU.SH LOG #######"

# Logging and desktop notification functions using Bash built-in timestamps
notify() {
    local message="$1"
    local urgency="${2:-normal}"
    printf '[%(%T)T] INFO: %s\n' -1 "$message"
    if command -v notify-send >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        notify-send -u "$urgency" -a "LMU" -t 4000 "Le Mans Ultimate" "$message" 2>/dev/null || true
    fi
}

errlog() {
    local message="$1"
    printf '[%(%T)T] ERROR: %s\n' -1 "$message" >&2
    if command -v notify-send >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        notify-send -u critical -a "LMU" "Le Mans Ultimate - Error" "$message" 2>/dev/null || true
    fi
}

debuglog() {
    if [[ "${DEBUG:-false}" == true ]]; then
        printf '[%(%T)T] DEBUG: %s\n' -1 "$1" >&2
    fi
}

# Read environment variables from launch_lmu.env
ENV_PATH="${SCRIPT_PATH}/launch_lmu.env"
if [[ -f "$ENV_PATH" ]]; then
    printf 'Environment file: %s\n' "$ENV_PATH"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_PATH"
    set +a
else
    errlog "Environment file $ENV_PATH not found. Exiting!"
    exit 1
fi

# Disable Proton's xalia.exe gamepad UI helper by default, as it continuously
# polls CrewChief's WinForms controls via broken Wine COM/UIA accessibility
# bridges and causes UI/COM resource leaks.
export PROTON_NO_XALIA="${PROTON_NO_XALIA:-1}"

DEBUG="${DEBUG:-false}"
if [[ "$DEBUG" != true && "$DEBUG" != false ]]; then
    errlog "DEBUG must be true or false, got: $DEBUG"
    exit 1
fi

CONFIGURE_SHARED_MEMORY_PLUGIN="${CONFIGURE_SHARED_MEMORY_PLUGIN:-true}"
if [[ "$CONFIGURE_SHARED_MEMORY_PLUGIN" != true && "$CONFIGURE_SHARED_MEMORY_PLUGIN" != false ]]; then
    errlog "CONFIGURE_SHARED_MEMORY_PLUGIN must be true or false, got: $CONFIGURE_SHARED_MEMORY_PLUGIN"
    exit 1
fi

require_executable() {
    local variable_name="$1"
    local executable_path="$2"
    local description="$3"

    if [[ -z "$executable_path" ]]; then
        errlog "Set $variable_name in $ENV_PATH."
        exit 1
    elif [[ ! -e "$executable_path" ]]; then
        errlog "$description not found at: $executable_path (check $variable_name in $ENV_PATH)"
        exit 1
    elif [[ ! -f "$executable_path" || ! -x "$executable_path" ]]; then
        errlog "$description is not an executable file: $executable_path (check $variable_name in $ENV_PATH)"
        exit 1
    fi
    debuglog "Found $description at: $executable_path"
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        errlog "Required command not found: $command_name"
        exit 1
    fi
    debuglog "Found command: $command_name"
}

# Check required commands and executables before doing any work
commands=("gamemoderun" "jq" "notify-send" "pgrep" "pkill")
for cmd in "${commands[@]}"; do
    require_command "$cmd"
done

if [[ -n "${LMUBRIDGE_BIN:-}" ]]; then
    require_executable LMUBRIDGE_BIN "$LMUBRIDGE_BIN" "LMU Shared Memory Bridge executable"
fi
if [[ -n "${LMUSHM_BIN:-}" ]]; then
    require_executable LMUSHM_BIN "$LMUSHM_BIN" "LMU Shared Memory executable"
fi
if [[ -n "${LMUFFB_BIN:-}" ]]; then
    require_executable LMUFFB_BIN "$LMUFFB_BIN" "LMUFFB executable"
fi
if [[ -n "${CREWCHIEF_BIN:-}" ]]; then
    require_executable CREWCHIEF_BIN "$CREWCHIEF_BIN" "CrewChief executable"
    require_command "protontricks-launch"
fi

if [[ -z "${STEAM_COMPAT_TOOL_PATHS:-}" ]]; then
    errlog "This script must be launched by Steam with Proton."
    exit 1
fi

ACTIVE_PROTON_DIR="${STEAM_COMPAT_TOOL_PATHS%%:*}"
export PROTON_PATH="$ACTIVE_PROTON_DIR/proton"
if [[ ! -x "$PROTON_PATH" ]]; then
    errlog "Proton executable is missing or not executable: $PROTON_PATH"
    exit 1
fi
debuglog "Using Proton executable at: $PROTON_PATH"

# Dynamically locate the Le Mans Ultimate installation directory and Settings.JSON
LMU_INSTALL_DIR="${STEAM_COMPAT_INSTALL_PATH:-}"
if [[ -z "$LMU_INSTALL_DIR" ]]; then
    for arg in "$@"; do
        if [[ "$arg" == *"/Le Mans Ultimate/"* ]]; then
            LMU_INSTALL_DIR="${arg%%/Le Mans Ultimate*}/Le Mans Ultimate"
            break
        fi
    done
fi
if [[ -z "$LMU_INSTALL_DIR" ]]; then
    for lib in ${STEAM_COMPAT_LIBRARY_PATHS:-}; do
        if [[ -d "${lib}/steamapps/common/Le Mans Ultimate" ]]; then
            LMU_INSTALL_DIR="${lib}/steamapps/common/Le Mans Ultimate"
            break
        fi
    done
fi

if [[ -z "$LMU_INSTALL_DIR" || ! -d "$LMU_INSTALL_DIR" ]]; then
    errlog "Could not locate Le Mans Ultimate installation directory."
    exit 1
fi

LMU_SETTINGS_ORG="${LMU_INSTALL_DIR}/UserData/player/Settings.JSON"

if [[ -f "$LMU_SETTINGS_ORG" ]]; then
    LMU_SETTINGS_TMP="$(mktemp /tmp/lmu_settings.XXXXXX.json)"

    if jq \
      --arg qc1 "${QUICK_CHAT_1:-}" \
      --arg qc2 "${QUICK_CHAT_2:-}" \
      --arg qc3 "${QUICK_CHAT_3:-}" \
      --arg qc4 "${QUICK_CHAT_4:-}" \
      --arg qc5 "${QUICK_CHAT_5:-}" \
      --arg qc6 "${QUICK_CHAT_6:-}" \
      --arg qc7 "${QUICK_CHAT_7:-}" \
      --arg qc8 "${QUICK_CHAT_8:-}" \
      --arg qc9 "${QUICK_CHAT_9:-}" \
      --arg qc10 "${QUICK_CHAT_10:-}" \
      --arg qc11 "${QUICK_CHAT_11:-}" \
      --arg qc12 "${QUICK_CHAT_12:-}" \
      '.CHAT |= (
        if $qc1 != "" then . + {"Quick Chat #1": $qc1} else . end |
        if $qc2 != "" then . + {"Quick Chat #2": $qc2} else . end |
        if $qc3 != "" then . + {"Quick Chat #3": $qc3} else . end |
        if $qc4 != "" then . + {"Quick Chat #4": $qc4} else . end |
        if $qc5 != "" then . + {"Quick Chat #5": $qc5} else . end |
        if $qc6 != "" then . + {"Quick Chat #6": $qc6} else . end |
        if $qc7 != "" then . + {"Quick Chat #7": $qc7} else . end |
        if $qc8 != "" then . + {"Quick Chat #8": $qc8} else . end |
        if $qc9 != "" then . + {"Quick Chat #9": $qc9} else . end |
        if $qc10 != "" then . + {"Quick Chat #10": $qc10} else . end |
        if $qc11 != "" then . + {"Quick Chat #11": $qc11} else . end |
        if $qc12 != "" then . + {"Quick Chat #12": $qc12} else . end
      )' "$LMU_SETTINGS_ORG" > "$LMU_SETTINGS_TMP"; then
        mv -f "$LMU_SETTINGS_TMP" "$LMU_SETTINGS_ORG"
        debuglog "Updated Settings.JSON chat mappings successfully at: $LMU_SETTINGS_ORG"
    else
        rm -f -- "$LMU_SETTINGS_TMP"
        errlog "Failed to update Settings.JSON with jq."
    fi
else
    debuglog "Settings.JSON not found at $LMU_SETTINGS_ORG, skipping chat updates."
fi

# Configure CustomPluginVariables.JSON for Linux/Wine shared memory compatibility
if [[ "$CONFIGURE_SHARED_MEMORY_PLUGIN" == true ]]; then
    WINE_SMM_PLUGIN="${LMU_INSTALL_DIR}/Plugins/rFactor2SharedMemoryMapPlugin64_Wine.dll"
    if [[ ! -f "$WINE_SMM_PLUGIN" ]]; then
        errlog "Required Wine shared memory plugin not found at: $WINE_SMM_PLUGIN"
        exit 1
    fi

    LMU_PLUGIN_VARS="${LMU_INSTALL_DIR}/UserData/player/CustomPluginVariables.JSON"
    mkdir -p "${LMU_PLUGIN_VARS%/*}"
    LMU_PLUGIN_TMP="$(mktemp /tmp/lmu_plugins.XXXXXX.json)"
    if [[ -f "$LMU_PLUGIN_VARS" ]]; then
        PLUGIN_SOURCE="$LMU_PLUGIN_VARS"
    else
        PLUGIN_SOURCE="/dev/null"
    fi

    if jq -n --slurpfile existing "$PLUGIN_SOURCE" '
      ($existing[0] // {}) + {
        "ChatTransceiver.dll": {
          " Enabled": 1
        },
        "LMU.3.8.SharedMemoryMapPlugin.dll": {
          " Enabled": 0,
          "DebugISIInternals": 0,
          "DebugOutputLevel": 0,
          "DebugOutputSource": 1,
          "DedicatedServerMapGlobally": 0,
          "EnableDirectMemoryAccess": 0,
          "EnableHWControlInput": 1,
          "EnableRulesControlInput": 0,
          "EnableWeatherControlInput": 0,
          "UnsubscribedBuffersMask": 160
        },
        "rFactor2SharedMemoryMapPlugin64_Wine.dll": {
          " Enabled": 1,
          "DebugISIInternals": 0,
          "DebugOutputLevel": 0,
          "DebugOutputSource": 1,
          "DedicatedServerMapGlobally": 0,
          "EnableDirectMemoryAccess": 0,
          "EnableHWControlInput": 1,
          "EnableRulesControlInput": 0,
          "EnableWeatherControlInput": 0,
          "UnsubscribedBuffersMask": 160
        }
      }
    ' > "$LMU_PLUGIN_TMP"; then
        mv -f "$LMU_PLUGIN_TMP" "$LMU_PLUGIN_VARS"
        debuglog "Updated CustomPluginVariables.JSON successfully at: $LMU_PLUGIN_VARS"
    else
        rm -f -- "$LMU_PLUGIN_TMP"
        errlog "Failed to update CustomPluginVariables.JSON with jq at: $LMU_PLUGIN_VARS"
        exit 1
    fi
fi

# Ensure CrewChief profiles have use_naudio=false so Wine/Proton audio does not hang,
# and align legacy shared memory settings when CONFIGURE_SHARED_MEMORY_PLUGIN is enabled
if [[ -n "${CREWCHIEF_BIN:-}" && -n "${STEAM_COMPAT_DATA_PATH:-}" ]]; then
    CC_PROFILES_DIR="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser/Documents/CrewChiefV4/Profiles"
    if [[ -d "$CC_PROFILES_DIR" ]]; then
        for cc_profile in "$CC_PROFILES_DIR"/*.json; do
            [[ -f "$cc_profile" ]] || continue
            cc_profile_tmp="$(mktemp /tmp/cc_profile.XXXXXX.json)"
            if jq --argjson cfg_shm "$CONFIGURE_SHARED_MEMORY_PLUGIN" '
              if (.userSettings | type) == "object" then
                .userSettings.use_naudio = false |
                if $cfg_shm then
                  .userSettings.use_legacy_rf2_shared_memory_filenames = true |
                  .userSettings.enable_lmu_rf2_plugin_dll_check = false |
                  .userSettings.enable_automatic_plugin_update = false
                else . end
              else . end
            ' "$cc_profile" > "$cc_profile_tmp"; then
                mv -f "$cc_profile_tmp" "$cc_profile"
                debuglog "Verified/updated CrewChief profile settings at: $cc_profile"
            else
                rm -f -- "$cc_profile_tmp"
                errlog "Failed to update CrewChief profile with jq: $cc_profile"
            fi
        done
    else
        debuglog "CrewChief profiles directory not found at $CC_PROFILES_DIR, skipping profile update."
    fi
fi

# Ensure old instances aren't stuck in the background
if [[ -n "${LMUBRIDGE_BIN:-}" ]] && pgrep -f "lmubridge.exe" >/dev/null; then
    errlog "LMU Shared Memory Bridge is already running. Please close it before launching LMU."
    exit 1
fi

if [[ -n "${LMUFFB_BIN:-}" ]] && pgrep -f "LMUFFB.exe" >/dev/null; then
    errlog "LMUFFB is already running. Please close it before launching LMU."
    exit 1
fi

if [[ -n "${CREWCHIEF_BIN:-}" ]] && pgrep -f "CrewChiefV4.exe" >/dev/null; then
    errlog "CrewChief is already running. Please close it before launching LMU."
    exit 1
fi

# Helper: sleep in 1-second ticks, aborting immediately if LMU closes early
wait_while_lmu_running() {
    local seconds="$1"
    local i
    for ((i = 0; i < seconds; i++)); do
        if ! pgrep -f "Le Mans Ultimate.exe" >/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 0
}

# Graceful two-stage teardown (SIGTERM -> wait up to 3s -> SIGKILL)
LMUSHM_FIFO="${XDG_RUNTIME_DIR:-/tmp}/lmushm_$$.fifo"
CLEANUP_LOCK="${XDG_RUNTIME_DIR:-/tmp}/lmu_cleanup_$$.lock"

cleanup_helpers() {
    mkdir "$CLEANUP_LOCK" 2>/dev/null || return 0

    local targets=("CrewChiefV4.exe" "LMUFFB.exe" "lmubridge.exe")
    if [[ -n "${LMUSHM_BIN:-}" ]]; then
        targets+=("${LMUSHM_BIN##*/}")
    fi

    local running=()
    local target
    for target in "${targets[@]}"; do
        if pgrep -f "$target" >/dev/null 2>&1; then
            running+=("$target")
        fi
    done

    if (( ${#running[@]} > 0 )); then
        notify "Stopping helper processes: ${running[*]}"
        for target in "${running[@]}"; do
            pkill -TERM -f "$target" 2>/dev/null || true
        done

        # Give helpers up to 3 seconds to save configs and close shared memory cleanly
        local i still_alive
        for ((i = 0; i < 30; i++)); do
            still_alive=false
            for target in "${running[@]}"; do
                if pgrep -f "$target" >/dev/null 2>&1; then
                    still_alive=true
                    break
                fi
            done
            [[ "$still_alive" == false ]] && break
            sleep 0.1
        done

        # Force-kill anything still hanging the Wine prefix
        local failed_stop=()
        for target in "${running[@]}"; do
            if pgrep -f "$target" >/dev/null 2>&1; then
                debuglog "Force-killing lingering helper: $target"
                pkill -KILL -f "$target" 2>/dev/null || true
                sleep 0.1
                if pgrep -f "$target" >/dev/null 2>&1; then
                    failed_stop+=("$target")
                fi
            fi
        done

        if (( ${#failed_stop[@]} > 0 )); then
            errlog "Failed to stop helper processes: ${failed_stop[*]}"
        else
            notify "Stopped helper processes: ${running[*]}"
        fi
    fi

    rm -f -- "$LMUSHM_FIFO"
}

# Start lmushm using a read-write FIFO so stdin stays open without an orphaned 'tail' process
if [[ -n "${LMUSHM_BIN:-}" ]]; then
    if ! pgrep -f "$LMUSHM_BIN" >/dev/null; then
        LMUSHM_LOG="${LOG_DIR}/lmushm.log"
        rotate_log "$LMUSHM_LOG"
        notify "Starting lmushm..."
        rm -f -- "$LMUSHM_FIFO"
        mkfifo "$LMUSHM_FIFO"
        "$LMUSHM_BIN" <>"$LMUSHM_FIFO" >"$LMUSHM_LOG" 2>&1 &
        sleep 0.2
        if pgrep -f "$LMUSHM_BIN" >/dev/null; then
            notify "lmushm started."
        else
            errlog "lmushm failed to start ($LMUSHM_BIN). Check $LMUSHM_LOG."
            exit 1
        fi
    else
        debuglog "lmushm is already running."
    fi
fi

# Single background orchestrator for staggered startup and in-game exit detection
orchestrate_helpers() {
    local main_script_pid="$1"

    # 1. Wait for Le Mans Ultimate.exe to appear (abort if main script dies first)
    while ! pgrep -f "Le Mans Ultimate.exe" >/dev/null; do
        if ! kill -0 "$main_script_pid" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    notify "Le Mans Ultimate started."

    # 2. T+10s: Launch lmubridge via Proton wine64
    if [[ -n "${LMUBRIDGE_BIN:-}" ]]; then
        wait_while_lmu_running 10 || { cleanup_helpers; return 0; }
        local lmubridge_log="${LOG_DIR}/lmubridge.log"
        rotate_log "$lmubridge_log"
        notify "Starting LMU Shared Memory Bridge (lmubridge.exe)..."
        STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
        WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" \
        "$ACTIVE_PROTON_DIR/files/bin/wine64" "$LMUBRIDGE_BIN" \
            </dev/null >"$lmubridge_log" 2>&1 &

        wait_while_lmu_running 1 || { cleanup_helpers; return 0; }
        if pgrep -f "lmubridge.exe" >/dev/null; then
            notify "LMU Shared Memory Bridge started."
        else
            errlog "LMU Shared Memory Bridge (lmubridge.exe) failed to start. Check $lmubridge_log."
        fi
    fi

    # 3. T+15s (5s after lmubridge, or 15s if lmubridge is disabled): Launch LMUFFB
    if [[ -n "${LMUFFB_BIN:-}" ]]; then
        local ffb_delay=15
        [[ -n "${LMUBRIDGE_BIN:-}" ]] && ffb_delay=4
        wait_while_lmu_running "$ffb_delay" || { cleanup_helpers; return 0; }

        LMUFFB_DIR="${LMUFFB_BIN%/*}"
        LMUFFB_EXE="${LMUFFB_BIN##*/}"
        if [[ -d "$LMUFFB_DIR" ]]; then
            local lmuffb_log="${LOG_DIR}/lmuffb.log"
            rotate_log "$lmuffb_log"
            notify "Starting LMUFFB..."
            (
                cd "$LMUFFB_DIR" || exit 1
                STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
                WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" \
                exec "$ACTIVE_PROTON_DIR/files/bin/wine64" "./$LMUFFB_EXE" \
                    </dev/null >"$lmuffb_log" 2>&1
            ) &

            wait_while_lmu_running 1 || { cleanup_helpers; return 0; }
            if pgrep -f "LMUFFB.exe" >/dev/null; then
                notify "LMUFFB started."
            else
                errlog "LMUFFB failed to start. Check $lmuffb_log."
            fi
        else
            errlog "LMUFFB directory not found: $LMUFFB_DIR"
        fi
    fi

    # 4. T+45s: Launch CrewChief via protontricks-launch
    if [[ -n "${CREWCHIEF_BIN:-}" ]]; then
        local cc_delay=25
        if [[ -n "${LMUFFB_BIN:-}" ]]; then
            cc_delay=29
        elif [[ -n "${LMUBRIDGE_BIN:-}" ]]; then
            cc_delay=34
        fi
        wait_while_lmu_running "$cc_delay" || { cleanup_helpers; return 0; }

        local crewchief_log="${LOG_DIR}/crewchief.log"
        rotate_log "$crewchief_log"
        notify "Starting CrewChief..."

        (
            # Strip Steam Runtime paths from PATH and XDG_DATA_DIRS so host tools
            # and libraries are used cleanly, matching a standalone shell session
            clean_path=""
            IFS=':'
            for entry in $PATH; do
                if [[ "$entry" != *"/ubuntu12_"* && "$entry" != *"/steam-runtime"* ]]; then
                    clean_path="${clean_path:+${clean_path}:}${entry}"
                fi
            done
            export PATH="$clean_path"

            if [[ -n "${XDG_DATA_DIRS:-}" ]]; then
                clean_xdg=""
                for entry in $XDG_DATA_DIRS; do
                    if [[ "$entry" != *"/ubuntu12_"* && "$entry" != *"/steam-runtime"* ]]; then
                        clean_xdg="${clean_xdg:+${clean_xdg}:}${entry}"
                    fi
                done
                export XDG_DATA_DIRS="$clean_xdg"
            fi
            unset IFS

            # Unset Steam/Proton/runtime variables injected by Steam or launch_lmu.env
            while IFS= read -r var; do
                unset "$var"
            done < <(compgen -e STEAM_ || true; compgen -e Steam || true)

            unset LD_PRELOAD LD_LIBRARY_PATH \
                GSETTINGS_SCHEMA_DIR GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_PATH_1_0 \
                WINE_GST_REGISTRY_DIR ENABLE_VULKAN_RENDERDOC_CAPTURE \
                PROTON_PATH PROTON_LOG PROTON_USE_EAC_LINUX DXVK_ASYNC \
                WINEPREFIX WINEARCH WINE WINESERVER WINELOADER WINEDLLPATH

            export WINEDEBUG="-winegstreamer,-gstreamer"
            export PROTON_NO_XALIA=1
            export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-60}"
            export PROTON_VERSION="${PROTON_VERSION:-${ACTIVE_PROTON_DIR##*/}}"
            export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

            exec protontricks-launch --no-runtime --appid 2399420 "$CREWCHIEF_BIN" \
                </dev/null >>"$crewchief_log" 2>&1
        ) &
        local cc_launcher_pid=$!

        # Wait for CrewChiefV4.exe to start before continuing
        local cc_started=true
        while ! pgrep -f "CrewChiefV4.exe" >/dev/null; do
            if ! kill -0 "$cc_launcher_pid" 2>/dev/null; then
                errlog "CrewChief failed to start. Check $crewchief_log."
                cc_started=false
                break
            fi
            debuglog "Waiting for CrewChiefV4.exe to start..."
            wait_while_lmu_running 1 || { cleanup_helpers; return 0; }
        done
        if [[ "$cc_started" == true ]]; then
            notify "CrewChief started."
        fi
    fi

    # 5. Monitor Le Mans Ultimate.exe and trigger cleanup as soon as it closes
    #    (Required so helper .exe processes exit and let Proton's wineserver shut down)
    while pgrep -f "Le Mans Ultimate.exe" >/dev/null; do
        sleep 2
    done

    notify "Le Mans Ultimate stopped."
    cleanup_helpers
}

orchestrate_helpers "$$" &
ORCHESTRATOR_PID=$!

# Guarantee cleanup if Steam stops the game or the script exits early
on_script_exit() {
    unset LD_PRELOAD
    if [[ -d "$CLEANUP_LOCK" ]]; then
        wait "$ORCHESTRATOR_PID" 2>/dev/null || true
    else
        kill "$ORCHESTRATOR_PID" 2>/dev/null || true
        cleanup_helpers
    fi
    rm -rf -- "$CLEANUP_LOCK"
}
trap on_script_exit EXIT INT TERM

# Keep the main game in the foreground
notify "Starting Le Mans Ultimate..."
LD_PRELOAD="$STEAM_LD_PRELOAD" gamemoderun "$@"
