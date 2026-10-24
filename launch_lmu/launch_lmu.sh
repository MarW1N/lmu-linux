#!/usr/bin/env bash
set -euo pipefail

# Save Steam's LD_PRELOAD and clear it so helper commands don't emit ELFCLASS32 warnings
STEAM_LD_PRELOAD="${LD_PRELOAD-}"
unset LD_PRELOAD

# Launch LMU from Steam with these launch options:
# /path/to/launch_lmu.sh %command%

# Get the path to the directory containing this script
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Keep the active log and numbered archives together under logs/.
LOG_DIR="${SCRIPT_PATH}/logs"
[ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"
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

# Start a fresh log and capture all launcher output while keeping it visible
rotate_log "$LOG_FILE"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "####### BEGIN LAUNCH_LMU.SH LOG #######"

# Logging functions using Bash built-in timestamps
errlog() {
    printf '[%(%T)T] ERROR: %s\n' -1 "$1" >&2
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

DEBUG="${DEBUG:-false}"
if [[ "$DEBUG" != true && "$DEBUG" != false ]]; then
    errlog "DEBUG must be true or false, got: $DEBUG"
    exit 1
fi

require_executable() {
    local variable_name="$1"
    local executable_path="$2"
    local description="$3"

    if [[ -z "$executable_path" ]]; then
        errlog "Set $variable_name in $ENV_PATH."
        exit 1
    elif [[ ! -f "$executable_path" || ! -x "$executable_path" ]]; then
        errlog "$description is not an executable file: $executable_path"
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
    require_executable CREWCHIEF_BIN "${CREWCHIEF_BIN:-}" "CrewChief executable"
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

LMU_SETTINGS_ORG="${LMU_INSTALL_DIR}/UserData/player/Settings.JSON"

if [[ -f "$LMU_SETTINGS_ORG" ]]; then
    LMU_SETTINGS_TMP="$(mktemp /tmp/lmu_settings.XXXXXX.json)"
    
    jq \
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
      )' "$LMU_SETTINGS_ORG" > "$LMU_SETTINGS_TMP" && mv -f "$LMU_SETTINGS_TMP" "$LMU_SETTINGS_ORG"
    debuglog "Updated Settings.JSON chat mappings successfully at: $LMU_SETTINGS_ORG"
else
    debuglog "Settings.JSON not found at $LMU_SETTINGS_ORG, skipping chat updates."
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

# Start lmushm if configured and not already running
if [[ -n "${LMUSHM_BIN:-}" ]]; then
    if ! pgrep -f "$LMUSHM_BIN" >/dev/null; then
        debuglog "Starting lmushm..."
        ( tail -f /dev/null | "$LMUSHM_BIN" ) &
    else
        debuglog "lmushm is already running."
    fi
fi

# 1. Wait for Le Mans Ultimate.exe to appear, then launch lmubridge using Proton's direct wine64
if [[ -n "${LMUBRIDGE_BIN:-}" ]]; then
    (
    while ! pgrep -f "Le Mans Ultimate.exe" >/dev/null; do
        sleep 1
    done
    
    sleep 3
    debuglog "Launching lmubridge.exe via direct Proton wine64..."
    
    STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
    WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" \
    "$ACTIVE_PROTON_DIR/files/bin/wine64" "$LMUBRIDGE_BIN" &
    ) &
fi

# 2. Wait a bit longer, then launch LMUFFB directly from its directory subshell
if [[ -n "${LMUFFB_BIN:-}" ]]; then
    (
    while ! pgrep -f "Le Mans Ultimate.exe" >/dev/null; do
        sleep 1
    done
    sleep 8
    debuglog "Starting LMUFFB directly from its directory..."

    LMUFFB_DIR="${LMUFFB_BIN%/*}"
    LMUFFB_EXE="${LMUFFB_BIN##*/}"

    if [[ -d "$LMUFFB_DIR" ]]; then
        cd "$LMUFFB_DIR" || exit 1
        STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
        WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" \
        "$ACTIVE_PROTON_DIR/files/bin/wine64" "./$LMUFFB_EXE" &
    else
        errlog "LMUFFB directory not found: $LMUFFB_DIR"
    fi
    ) &
fi

# 3. Launch CrewChief when its executable is configured
if [[ -n "${CREWCHIEF_BIN:-}" ]]; then
    (
        while ! pgrep -f "Le Mans Ultimate.exe" >/dev/null; do
            sleep 1
        done
        
        sleep 45
        debuglog "Starting CrewChief..."
        
        export WINEDEBUG="-winegstreamer,-gstreamer"
        export WINEDLLOVERRIDES="winegstreamer=d"
        export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
        
        protontricks-launch --no-runtime --appid 2399420 "$CREWCHIEF_BIN" &
        
        # Wait for CrewChief to start and renice it to 19
        while ! pgrep -f "CrewChiefV4.exe" >/dev/null; do
            sleep 1
        done
        
        cc_pid=$(pgrep -f "CrewChiefV4.exe" | head -n1)
        if [[ -n "$cc_pid" ]]; then
            renice -n 19 -p "$cc_pid" >/dev/null 2>&1 || true
            debuglog "Reniced CrewChiefV4.exe (PID $cc_pid) to 19"
        fi
    ) &
fi

# 4. Cleanup loop (waits 45s initially so slow startups don't trigger early kills)
(
    sleep 60
    while pgrep -f "Le Mans Ultimate.exe" >/dev/null; do
        sleep 5
    done

    debuglog "Le Mans Ultimate closed. Terminating helper processes..."
    pkill -f "lmubridge.exe" || true
    pkill -f "lmushm" || true
    pkill -f "LMUFFB.exe" || true
    if [[ -n "${CREWCHIEF_BIN:-}" ]]; then
        pkill -f "CrewChiefV4.exe" || true
    fi
) &

# 5. Keep the main game in the foreground
export LD_PRELOAD="$STEAM_LD_PRELOAD"
gamemoderun "$@"
