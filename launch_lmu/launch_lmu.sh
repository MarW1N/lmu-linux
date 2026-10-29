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
# bridges and causes severe wineserver/UIA syscall storms.
# Proton 9/10+ checks PROTON_USE_XALIA=0; WINEDLLOVERRIDES blocks explorer.exe
# from spawning xalia.exe in direct wine64 / protontricks helper sessions.
export PROTON_USE_XALIA="${PROTON_USE_XALIA:-0}"
export PROTON_NO_XALIA="${PROTON_NO_XALIA:-1}"
if [[ "${PROTON_USE_XALIA}" == "0" ]]; then
    case ";${WINEDLLOVERRIDES:-};" in
        *";xalia.exe="* | *";xalia="*) ;;
        *) export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}xalia.exe=d" ;;
    esac
fi

require_boolean() {
    local var_name="$1"
    local var_value="$2"
    if [[ "$var_value" != true && "$var_value" != false ]]; then
        errlog "$var_name must be true or false, got: $var_value"
        exit 1
    fi
}

require_nonneg_int() {
    local var_name="$1"
    local var_value="$2"
    if [[ ! "$var_value" =~ ^[0-9]+$ ]]; then
        errlog "$var_name must be a non-negative integer, got: $var_value"
        exit 1
    fi
}

DEBUG="${DEBUG:-false}"
require_boolean DEBUG "$DEBUG"

CONFIGURE_SHARED_MEMORY_PLUGIN="${CONFIGURE_SHARED_MEMORY_PLUGIN:-true}"
require_boolean CONFIGURE_SHARED_MEMORY_PLUGIN "$CONFIGURE_SHARED_MEMORY_PLUGIN"

USE_GAMEMODE="${USE_GAMEMODE:-true}"
require_boolean USE_GAMEMODE "$USE_GAMEMODE"

LMUBRIDGE_DELAY="${LMUBRIDGE_DELAY:-10}"
require_nonneg_int LMUBRIDGE_DELAY "$LMUBRIDGE_DELAY"

LMUFFB_DELAY="${LMUFFB_DELAY:-15}"
require_nonneg_int LMUFFB_DELAY "$LMUFFB_DELAY"

CREWCHIEF_DELAY="${CREWCHIEF_DELAY:-35}"
require_nonneg_int CREWCHIEF_DELAY "$CREWCHIEF_DELAY"

CREWCHIEF_STARTUP_TIMEOUT="${CREWCHIEF_STARTUP_TIMEOUT:-30}"
require_nonneg_int CREWCHIEF_STARTUP_TIMEOUT "$CREWCHIEF_STARTUP_TIMEOUT"

LMU_APP_ID="${SteamAppId:-${STEAM_COMPAT_APP_ID:-2399420}}"

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
commands=("jq" "pgrep" "pkill")
for cmd in "${commands[@]}"; do
    require_command "$cmd"
done
if ! command -v notify-send >/dev/null 2>&1; then
    debuglog "Optional command notify-send not found; desktop notifications disabled."
fi

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
if [[ -z "$LMU_INSTALL_DIR" && -n "${STEAM_COMPAT_LIBRARY_PATHS:-}" ]]; then
    IFS=':' read -r -a compat_libs <<< "$STEAM_COMPAT_LIBRARY_PATHS"
    for lib in "${compat_libs[@]}"; do
        if [[ -n "$lib" && -d "${lib}/steamapps/common/Le Mans Ultimate" ]]; then
            LMU_INSTALL_DIR="${lib}/steamapps/common/Le Mans Ultimate"
            break
        fi
    done
fi

if [[ -z "$LMU_INSTALL_DIR" || ! -d "$LMU_INSTALL_DIR" ]]; then
    errlog "Could not locate Le Mans Ultimate installation directory."
    exit 1
fi

# Atomically replace a JSON config file on the same filesystem only when contents differ
commit_temp_json() {
    local tmp_file="$1"
    local target_file="$2"
    local label="$3"

    if [[ -f "$target_file" ]] && cmp -s "$tmp_file" "$target_file"; then
        rm -f -- "$tmp_file"
        debuglog "$label already up to date at: $target_file"
        return 0
    fi

    if [[ -f "$target_file" ]]; then
        chmod --reference="$target_file" "$tmp_file" 2>/dev/null || chmod 0644 "$tmp_file"
    else
        chmod 0644 "$tmp_file"
    fi
    mv -f -- "$tmp_file" "$target_file"
    debuglog "Updated $label successfully at: $target_file"
}

LMU_SETTINGS_ORG="${LMU_INSTALL_DIR}/UserData/player/Settings.JSON"
HAS_QUICK_CHAT_OVERRIDES=false
if [[ -n "${QUICK_CHAT_1:-}${QUICK_CHAT_2:-}${QUICK_CHAT_3:-}${QUICK_CHAT_4:-}${QUICK_CHAT_5:-}${QUICK_CHAT_6:-}${QUICK_CHAT_7:-}${QUICK_CHAT_8:-}${QUICK_CHAT_9:-}${QUICK_CHAT_10:-}${QUICK_CHAT_11:-}${QUICK_CHAT_12:-}" ]]; then
    HAS_QUICK_CHAT_OVERRIDES=true
fi

if [[ "$HAS_QUICK_CHAT_OVERRIDES" == false ]]; then
    debuglog "No QUICK_CHAT_* overrides configured; leaving Settings.JSON untouched."
elif [[ -f "$LMU_SETTINGS_ORG" ]]; then
    LMU_SETTINGS_TMP="$(mktemp "${LMU_SETTINGS_ORG%/*}/.Settings.JSON.tmp.XXXXXX")"

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
        commit_temp_json "$LMU_SETTINGS_TMP" "$LMU_SETTINGS_ORG" "Settings.JSON chat mappings"
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
    LMU_PLUGIN_TMP="$(mktemp "${LMU_PLUGIN_VARS%/*}/.CustomPluginVariables.JSON.tmp.XXXXXX")"
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
        commit_temp_json "$LMU_PLUGIN_TMP" "$LMU_PLUGIN_VARS" "CustomPluginVariables.JSON"
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
            cc_profile_tmp="$(mktemp "${CC_PROFILES_DIR}/.${cc_profile##*/}.tmp.XXXXXX")"
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
                commit_temp_json "$cc_profile_tmp" "$cc_profile" "CrewChief profile (${cc_profile##*/})"
            else
                rm -f -- "$cc_profile_tmp"
                errlog "Failed to update CrewChief profile with jq: $cc_profile"
            fi
        done
    else
        debuglog "CrewChief profiles directory not found at $CC_PROFILES_DIR, skipping profile update."
    fi
fi

# Exact process-name helpers (Linux /proc/<pid>/comm is truncated to 15 chars,
# and unreaped zombie 'Z' processes are ignored)
pid_is_alive() {
    local pid="$1"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || return 1
    if [[ -r "/proc/${pid}/stat" ]]; then
        local stat_line="" state_part=""
        IFS= read -r stat_line < "/proc/${pid}/stat" || return 1
        state_part="${stat_line##*) }"
        [[ "${state_part:0:1}" != "Z" ]] || return 1
    fi
    return 0
}

helper_comm_name() {
    local base="${1##*/}"
    printf '%s' "${base:0:15}"
}

helper_is_running() {
    local comm_name pid
    comm_name="$(helper_comm_name "$1")"
    while IFS= read -r pid; do
        if pid_is_alive "$pid"; then
            return 0
        fi
    done < <(pgrep -x "$comm_name" 2>/dev/null || true)
    return 1
}

# Ensure old instances aren't stuck in the background
if [[ -n "${LMUBRIDGE_BIN:-}" ]] && helper_is_running "$LMUBRIDGE_BIN"; then
    errlog "LMU Shared Memory Bridge is already running. Please close it before launching LMU."
    exit 1
fi

if [[ -n "${LMUFFB_BIN:-}" ]] && helper_is_running "$LMUFFB_BIN"; then
    errlog "LMUFFB is already running. Please close it before launching LMU."
    exit 1
fi

if [[ -n "${CREWCHIEF_BIN:-}" ]] && helper_is_running "$CREWCHIEF_BIN"; then
    errlog "CrewChief is already running. Please close it before launching LMU."
    exit 1
fi

# Cache Le Mans Ultimate.exe PID once found so monitoring uses zero-fork kill -0 checks
LMU_EXE_PID=""

lmu_is_running() {
    if pid_is_alive "$LMU_EXE_PID"; then
        if [[ -r "/proc/${LMU_EXE_PID}/comm" ]]; then
            local comm=""
            IFS= read -r comm < "/proc/${LMU_EXE_PID}/comm" || true
            if [[ "$comm" == "Le Mans Ultimat"* ]]; then
                return 0
            fi
        fi
    fi

    local pids="" pid
    LMU_EXE_PID=""
    pids="$(pgrep -x "Le Mans Ultimat" 2>/dev/null || true)"
    if [[ -z "$pids" ]]; then
        pids="$(pgrep -f "Le Mans Ultimate\\.exe" 2>/dev/null || true)"
    fi
    while IFS= read -r pid; do
        if pid_is_alive "$pid"; then
            LMU_EXE_PID="$pid"
            return 0
        fi
    done <<< "$pids"
    return 1
}

# Helper: interruptible sleep inside orchestrate_helpers (wakes immediately on SIGTERM without stderr noise)
orchestrate_sleep() {
    local sleep_pid
    sleep "$1" &
    sleep_pid=$!
    # shellcheck disable=SC2064
    trap "kill -TERM $sleep_pid 2>/dev/null || true; exit 0" TERM INT
    wait "$sleep_pid" 2>/dev/null || true
    trap 'exit 0' TERM INT
}

# Helper: sleep in 1-second ticks, aborting immediately if LMU closes early
wait_while_lmu_running() {
    local seconds="$1"
    local i
    for ((i = 0; i < seconds; i++)); do
        if ! lmu_is_running; then
            return 1
        fi
        orchestrate_sleep 1
    done
    return 0
}

# Helper: wait until SECONDS reaches target_seconds since LMU started
wait_until_lmu_elapsed() {
    local target_seconds="$1"
    while (( SECONDS < target_seconds )); do
        if ! lmu_is_running; then
            return 1
        fi
        orchestrate_sleep 1
    done
    lmu_is_running
}

# Copy WINEFSYNC / WINEESYNC / WINENTSYNC from the active Proton wineserver so
# helper processes use the exact same kernel sync primitives instead of falling
# back to heavy single-threaded wineserver socket RPCs.
HELPER_WINE_SYNC_ARGS=()

load_wineserver_sync_env() {
    local target_prefix="${STEAM_COMPAT_DATA_PATH}/pfx"
    local target_real="$target_prefix"
    if command -v realpath >/dev/null 2>&1; then
        target_real="$(realpath "$target_prefix" 2>/dev/null || printf '%s' "$target_prefix")"
    fi

    local ws_pid entry key val val_real
    HELPER_WINE_SYNC_ARGS=()

    while IFS= read -r ws_pid; do
        [[ -n "$ws_pid" && -r "/proc/${ws_pid}/environ" ]] || continue
        local match_prefix=false
        local sync_vars=()
        while IFS= read -r -d '' entry; do
            key="${entry%%=*}"
            val="${entry#*=}"
            case "$key" in
                WINEPREFIX)
                    val_real="$val"
                    if command -v realpath >/dev/null 2>&1; then
                        val_real="$(realpath "$val" 2>/dev/null || printf '%s' "$val")"
                    fi
                    if [[ "$val" == "$target_prefix" || "$val_real" == "$target_real" || "$val" == *"/compatdata/${LMU_APP_ID}/"* ]]; then
                        match_prefix=true
                    fi
                    ;;
                WINEFSYNC|WINEESYNC|WINENTSYNC|PROTON_USE_NTSYNC|PROTON_NO_FSYNC|PROTON_NO_ESYNC)
                    sync_vars+=("${key}=${val}")
                    ;;
            esac
        done < "/proc/${ws_pid}/environ"

        if [[ "$match_prefix" == true ]]; then
            HELPER_WINE_SYNC_ARGS=("${sync_vars[@]}")
            debuglog "Copied sync env from wineserver (PID ${ws_pid}): ${HELPER_WINE_SYNC_ARGS[*]}"
            return 0
        fi
    done < <(pgrep -x "wineserver" || true)

    debuglog "Could not match running wineserver for $target_prefix; helpers will use default sync env."
}

# Graceful two-stage teardown (SIGTERM -> wait up to 3s -> SIGKILL)
LMUSHM_FIFO="${XDG_RUNTIME_DIR:-/tmp}/lmushm_$$.fifo"
CLEANUP_LOCK="${XDG_RUNTIME_DIR:-/tmp}/lmu_cleanup_$$.lock"
CC_LAUNCHER_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/lmu_cc_launcher_$$.pid"
LMUSHM_PID=""
ORCHESTRATOR_PID=""

cleanup_helpers() {
    mkdir "$CLEANUP_LOCK" 2>/dev/null || return 0

    local cc_launcher_pid=""
    if [[ -r "$CC_LAUNCHER_PID_FILE" ]]; then
        IFS= read -r cc_launcher_pid < "$CC_LAUNCHER_PID_FILE" || true
    fi
    rm -f -- "$CC_LAUNCHER_PID_FILE"

    local configured_wine_helpers=()
    [[ -n "${CREWCHIEF_BIN:-}" ]] && configured_wine_helpers+=("${CREWCHIEF_BIN##*/}")
    [[ -n "${LMUFFB_BIN:-}" ]] && configured_wine_helpers+=("${LMUFFB_BIN##*/}")
    [[ -n "${LMUBRIDGE_BIN:-}" ]] && configured_wine_helpers+=("${LMUBRIDGE_BIN##*/}")

    local running_wine=()
    local running_labels=()
    local target
    for target in "${configured_wine_helpers[@]}"; do
        if helper_is_running "$target"; then
            running_wine+=("$target")
            running_labels+=("$target")
        fi
    done

    local stop_lmushm=false
    if pid_is_alive "$LMUSHM_PID"; then
        stop_lmushm=true
        running_labels+=("${LMUSHM_BIN##*/}")
    fi

    local stop_cc_launcher=false
    if pid_is_alive "$cc_launcher_pid"; then
        stop_cc_launcher=true
        if [[ -n "${CREWCHIEF_BIN:-}" ]] && ! helper_is_running "$CREWCHIEF_BIN"; then
            running_labels+=("protontricks-launch")
        fi
    fi

    if (( ${#running_labels[@]} > 0 )); then
        notify "Stopping helper processes: ${running_labels[*]}"
        if [[ "$stop_cc_launcher" == true ]]; then
            kill -TERM "$cc_launcher_pid" 2>/dev/null || true
        fi
        for target in "${running_wine[@]}"; do
            pkill -TERM -x "$(helper_comm_name "$target")" 2>/dev/null || true
        done
        if [[ "$stop_lmushm" == true ]]; then
            kill -TERM "$LMUSHM_PID" 2>/dev/null || true
        fi

        # Give helpers up to 3 seconds to save configs and close shared memory cleanly
        local i still_alive
        for ((i = 0; i < 30; i++)); do
            still_alive=false
            for target in "${running_wine[@]}"; do
                if helper_is_running "$target"; then
                    still_alive=true
                    break
                fi
            done
            if [[ "$still_alive" == false && "$stop_lmushm" == true ]] && pid_is_alive "$LMUSHM_PID"; then
                still_alive=true
            fi
            if [[ "$still_alive" == false && "$stop_cc_launcher" == true ]] && pid_is_alive "$cc_launcher_pid"; then
                still_alive=true
            fi
            [[ "$still_alive" == false ]] && break
            sleep 0.1
        done

        # Force-kill anything still hanging the Wine prefix
        local failed_stop=()
        if [[ "$stop_cc_launcher" == true ]] && pid_is_alive "$cc_launcher_pid"; then
            kill -KILL "$cc_launcher_pid" 2>/dev/null || true
        fi
        for target in "${running_wine[@]}"; do
            if helper_is_running "$target"; then
                debuglog "Force-killing lingering helper: $target"
                pkill -KILL -x "$(helper_comm_name "$target")" 2>/dev/null || true
                sleep 0.1
                if helper_is_running "$target"; then
                    failed_stop+=("$target")
                fi
            fi
        done
        if [[ "$stop_lmushm" == true ]] && pid_is_alive "$LMUSHM_PID"; then
            debuglog "Force-killing lingering helper: ${LMUSHM_BIN##*/} (PID $LMUSHM_PID)"
            kill -KILL "$LMUSHM_PID" 2>/dev/null || true
            sleep 0.1
            if pid_is_alive "$LMUSHM_PID"; then
                failed_stop+=("${LMUSHM_BIN##*/}")
            fi
        fi

        if (( ${#failed_stop[@]} > 0 )); then
            errlog "Failed to stop helper processes: ${failed_stop[*]}"
        else
            notify "Stopped helper processes: ${running_labels[*]}"
        fi
    fi

    rm -f -- "$LMUSHM_FIFO"
}

# Guarantee cleanup if Steam stops the game or the script exits early
on_script_exit() {
    local exit_code=$?
    trap - EXIT INT TERM
    unset LD_PRELOAD

    if [[ -d "$CLEANUP_LOCK" ]]; then
        if [[ -n "$ORCHESTRATOR_PID" ]]; then
            wait "$ORCHESTRATOR_PID" 2>/dev/null || true
        fi
    else
        cleanup_helpers
        if [[ -n "$ORCHESTRATOR_PID" ]]; then
            kill -TERM "$ORCHESTRATOR_PID" 2>/dev/null || true
            wait "$ORCHESTRATOR_PID" 2>/dev/null || true
        fi
    fi

    if [[ -n "$LMUSHM_PID" ]]; then
        wait "$LMUSHM_PID" 2>/dev/null || true
    fi

    rm -f -- "$LMUSHM_FIFO" "$CC_LAUNCHER_PID_FILE"
    rm -rf -- "$CLEANUP_LOCK"
    exit "$exit_code"
}
trap on_script_exit EXIT INT TERM

# Start lmushm using a read-write FIFO so stdin stays open without an orphaned 'tail' process
if [[ -n "${LMUSHM_BIN:-}" ]]; then
    if ! helper_is_running "$LMUSHM_BIN"; then
        LMUSHM_LOG="${LOG_DIR}/lmushm.log"
        rotate_log "$LMUSHM_LOG"
        notify "Starting lmushm..."
        rm -f -- "$LMUSHM_FIFO"
        mkfifo "$LMUSHM_FIFO"
        "$LMUSHM_BIN" <>"$LMUSHM_FIFO" >"$LMUSHM_LOG" 2>&1 &
        LMUSHM_PID=$!
        sleep 0.2
        if pid_is_alive "$LMUSHM_PID"; then
            notify "lmushm started."
        else
            LMUSHM_PID=""
            errlog "lmushm failed to start ($LMUSHM_BIN). Check $LMUSHM_LOG."
            exit 1
        fi
    else
        debuglog "lmushm is already running externally; leaving its lifecycle untouched."
    fi
fi

# Single background orchestrator for staggered startup and in-game exit detection
orchestrate_helpers() {
    trap 'exit 0' TERM INT
    local main_script_pid="$1"
    local helper_winedebug="-all"
    [[ "$DEBUG" == true ]] && helper_winedebug="-winegstreamer,-gstreamer"

    # 1. Wait for Le Mans Ultimate.exe to appear (abort if main script dies first)
    while ! lmu_is_running; do
        if ! pid_is_alive "$main_script_pid"; then
            return 0
        fi
        orchestrate_sleep 1
    done
    SECONDS=0
    notify "Le Mans Ultimate started."
    load_wineserver_sync_env

    # 2. Default T+10s (LMUBRIDGE_DELAY): Launch lmubridge via Proton wine64
    if [[ -n "${LMUBRIDGE_BIN:-}" ]]; then
        wait_until_lmu_elapsed "$LMUBRIDGE_DELAY" || { cleanup_helpers; return 0; }
        [[ ${#HELPER_WINE_SYNC_ARGS[@]} -eq 0 ]] && load_wineserver_sync_env
        local lmubridge_log="${LOG_DIR}/lmubridge.log"
        rotate_log "$lmubridge_log"
        notify "Starting LMU Shared Memory Bridge (${LMUBRIDGE_BIN##*/})..."
        (
            [[ ${#HELPER_WINE_SYNC_ARGS[@]} -gt 0 ]] && export "${HELPER_WINE_SYNC_ARGS[@]}"
            export STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH"
            export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
            export PROTON_USE_XALIA=0
            export PROTON_NO_XALIA=1
            export WINEDEBUG="$helper_winedebug"
            export WINEDLLOVERRIDES="xalia.exe=d"
            exec "$ACTIVE_PROTON_DIR/files/bin/wine64" "$LMUBRIDGE_BIN" \
                </dev/null >"$lmubridge_log" 2>&1
        ) &

        wait_while_lmu_running 1 || { cleanup_helpers; return 0; }
        if helper_is_running "$LMUBRIDGE_BIN"; then
            notify "LMU Shared Memory Bridge started."
        else
            errlog "LMU Shared Memory Bridge (${LMUBRIDGE_BIN##*/}) failed to start. Check $lmubridge_log."
        fi
    fi

    # 3. Default T+15s (LMUFFB_DELAY): Launch LMUFFB
    if [[ -n "${LMUFFB_BIN:-}" ]]; then
        wait_until_lmu_elapsed "$LMUFFB_DELAY" || { cleanup_helpers; return 0; }
        [[ ${#HELPER_WINE_SYNC_ARGS[@]} -eq 0 ]] && load_wineserver_sync_env

        local lmuffb_dir="${LMUFFB_BIN%/*}"
        local lmuffb_exe="${LMUFFB_BIN##*/}"
        if [[ -d "$lmuffb_dir" ]]; then
            local lmuffb_log="${LOG_DIR}/lmuffb.log"
            rotate_log "$lmuffb_log"
            notify "Starting LMUFFB..."
            (
                cd "$lmuffb_dir" || exit 1
                [[ ${#HELPER_WINE_SYNC_ARGS[@]} -gt 0 ]] && export "${HELPER_WINE_SYNC_ARGS[@]}"
                export STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH"
                export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
                export PROTON_USE_XALIA=0
                export PROTON_NO_XALIA=1
                export WINEDEBUG="$helper_winedebug"
                export WINEDLLOVERRIDES="xalia.exe=d"
                exec "$ACTIVE_PROTON_DIR/files/bin/wine64" "./$lmuffb_exe" \
                    </dev/null >"$lmuffb_log" 2>&1
            ) &

            wait_while_lmu_running 1 || { cleanup_helpers; return 0; }
            if helper_is_running "$LMUFFB_BIN"; then
                notify "LMUFFB started."
            else
                errlog "LMUFFB failed to start. Check $lmuffb_log."
            fi
        else
            errlog "LMUFFB directory not found: $lmuffb_dir"
        fi
    fi

    # 4. Default T+35s (CREWCHIEF_DELAY): Launch CrewChief via protontricks-launch
    if [[ -n "${CREWCHIEF_BIN:-}" ]]; then
        wait_until_lmu_elapsed "$CREWCHIEF_DELAY" || { cleanup_helpers; return 0; }
        [[ ${#HELPER_WINE_SYNC_ARGS[@]} -eq 0 ]] && load_wineserver_sync_env

        local crewchief_log="${LOG_DIR}/crewchief.log"
        rotate_log "$crewchief_log"
        notify "Starting CrewChief..."

        (
            # Strip Steam Runtime paths from PATH and XDG_DATA_DIRS so host tools
            # and libraries are used cleanly, matching a standalone shell session
            clean_path=""
            path_entries=()
            IFS=':' read -r -a path_entries <<< "${PATH:-}"
            for entry in "${path_entries[@]}"; do
                if [[ -n "$entry" && "$entry" != *"/ubuntu12_"* && "$entry" != *"/steam-runtime"* ]]; then
                    clean_path="${clean_path:+${clean_path}:}${entry}"
                fi
            done
            export PATH="$clean_path"

            if [[ -n "${XDG_DATA_DIRS:-}" ]]; then
                clean_xdg=""
                xdg_entries=()
                IFS=':' read -r -a xdg_entries <<< "$XDG_DATA_DIRS"
                for entry in "${xdg_entries[@]}"; do
                    if [[ -n "$entry" && "$entry" != *"/ubuntu12_"* && "$entry" != *"/steam-runtime"* ]]; then
                        clean_xdg="${clean_xdg:+${clean_xdg}:}${entry}"
                    fi
                done
                export XDG_DATA_DIRS="$clean_xdg"
            fi

            # Unset Steam/Proton/runtime variables injected by Steam or launch_lmu.env
            while IFS= read -r var; do
                unset "$var"
            done < <(compgen -e STEAM_ || true; compgen -e Steam || true)

            unset LD_PRELOAD LD_LIBRARY_PATH \
                GSETTINGS_SCHEMA_DIR GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_PATH_1_0 \
                WINE_GST_REGISTRY_DIR ENABLE_VULKAN_RENDERDOC_CAPTURE \
                PROTON_PATH PROTON_LOG PROTON_USE_EAC_LINUX DXVK_ASYNC \
                WINEPREFIX WINEARCH WINE WINESERVER WINELOADER WINEDLLPATH

            # Match wineserver sync primitives (including WINENTSYNC) and prevent
            # protontricks from injecting DXVK/NVAPI or spawning xalia.exe
            [[ ${#HELPER_WINE_SYNC_ARGS[@]} -gt 0 ]] && export "${HELPER_WINE_SYNC_ARGS[@]}"
            export WINEDEBUG="$helper_winedebug"
            export PROTON_USE_XALIA=0
            export PROTON_NO_XALIA=1
            export DXVK_ENABLE_NVAPI=0
            export WINEDLLOVERRIDES="dxgi,d3d9,d3d10core,d3d11,d3d12,d3d12core=b;nvapi,nvapi64,nvofapi64=d;winegstreamer=d;xalia.exe=d"
            export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-60}"
            export PROTON_VERSION="${PROTON_VERSION:-${ACTIVE_PROTON_DIR##*/}}"

            cc_locale="C.UTF-8"
            if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qi '^en_us\.utf-\?8$'; then
                cc_locale="en_US.UTF-8"
            fi
            export LC_ALL="$cc_locale" LANG="$cc_locale"

            exec protontricks-launch --no-runtime --appid "$LMU_APP_ID" "$CREWCHIEF_BIN" \
                </dev/null >"$crewchief_log" 2>&1
        ) &
        local cc_launcher_pid=$!
        printf '%s\n' "$cc_launcher_pid" > "$CC_LAUNCHER_PID_FILE"

        # Wait up to CREWCHIEF_STARTUP_TIMEOUT seconds for the real CrewChiefV4.exe Wine process
        local cc_started=false
        local cc_wait=0
        while (( cc_wait < CREWCHIEF_STARTUP_TIMEOUT )); do
            if helper_is_running "$CREWCHIEF_BIN"; then
                cc_started=true
                break
            fi
            if ! pid_is_alive "$cc_launcher_pid"; then
                errlog "CrewChief failed to start. Check $crewchief_log."
                break
            fi
            debuglog "Waiting for ${CREWCHIEF_BIN##*/} to start... (${cc_wait}s/${CREWCHIEF_STARTUP_TIMEOUT}s)"
            if ! wait_while_lmu_running 1; then
                cleanup_helpers
                return 0
            fi
            cc_wait=$((cc_wait + 1))
        done
        rm -f -- "$CC_LAUNCHER_PID_FILE"

        if [[ "$cc_started" == true ]]; then
            notify "CrewChief started."
        elif pid_is_alive "$cc_launcher_pid"; then
            errlog "Timed out after ${CREWCHIEF_STARTUP_TIMEOUT}s waiting for ${CREWCHIEF_BIN##*/}. Check $crewchief_log."
        fi
    fi

    # 5. Monitor Le Mans Ultimate.exe and trigger cleanup as soon as it closes
    #    (Required so helper .exe processes exit and let Proton's wineserver shut down)
    while lmu_is_running; do
        orchestrate_sleep 2
    done

    notify "Le Mans Ultimate stopped."
    cleanup_helpers
}

orchestrate_helpers "$$" &
ORCHESTRATOR_PID=$!

# Keep the main game in the foreground
notify "Starting Le Mans Ultimate..."
if [[ "$USE_GAMEMODE" == true ]]; then
    if command -v gamemoderun >/dev/null 2>&1; then
        LD_PRELOAD="$STEAM_LD_PRELOAD" gamemoderun "$@"
    else
        notify "gamemoderun not found; launching without GameMode." "low"
        LD_PRELOAD="$STEAM_LD_PRELOAD" "$@"
    fi
else
    LD_PRELOAD="$STEAM_LD_PRELOAD" "$@"
fi
