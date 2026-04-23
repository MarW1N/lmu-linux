#!/usr/bin/env bash

# This script is designed to launch Le Mans Ultimate
# with the LMU Shared Memory Bridge (lmubridge.exe)
# and the shared memory process (LMUSHM_PATH) on Linux using Proton.
# It also includes optimizations for better performance
# and a simple notification system to track the launch process.
# Launch LMU from Steam with these launch options:
#
# /path/to/launch_lmu.sh %command%

# Set the path to the LMU Shared Memory Bridge and shared memory executable
# Put environment variables in lmu.env in the same directory as this script
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ENV_PATH="${SCRIPT_PATH}/launch_lmu.env"
[ -f "$ENV_PATH" ] || { notify "Warning: Environment file $ENV_PATH not found. Exiting!"; exit 1; }
LOG_FILE="${SCRIPT_PATH}/launch_lmu.log"

# Clean up old log file if it exists
if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE"
fi

debuglog() {
    if [ "$DEBUG" = true ]; then
         echo "[$(date +'%T')] $1" >> "$LOG_FILE"
    fi
}

notify() {
    debuglog "$1"
    if [ -n "$DISPLAY" ]; then
        notify-send -a "LMU" -t 1000 "$1"
    fi
}

debuglog "Environment file: $ENV_PATH"

# Read environment variables from the lmu.env file if it exists
if [ -f "$ENV_PATH" ]; then
    set -a                 # Automatically export all variables defined after this point
    source "$ENV_PATH"     # Read the variables
    set +a                 # Stop automatically exporting
fi

# Construct paths to the LMU Bridge and shared memory executables
LMUBRIDGE_PATH="${SIMSHMBRIDGE_PATH}/lmubridge.exe"
LMUSHM_PATH="${SIMSHMBRIDGE_PATH}/lmushm"
debuglog "lmubridge.exe path: $LMUBRIDGE_PATH"
debuglog "lmushm path: $LMUSHM_PATH"

# Validate that the required executables exist and are executable
if ! [[ -f "$LMUSHM_PATH" && -x "$LMUSHM_PATH" ]]; then
    notify "Error: LMU Shared Memory executable not found at $LMUSHM_PATH or not executable. Exiting!"
    exit 1
fi

if ! [[ -f "$LMUBRIDGE_PATH" && -x "$LMUBRIDGE_PATH" ]]; then
    notify "Error: LMU Bridge executable not found at $LMUBRIDGE_PATH or not executable. Exiting!"
    exit 1
fi

if ! command -v protontricks-launch >/dev/null 2>&1; then
    notify "Error: protontricks-launch could not be found. Exiting!"
    exit 1
fi

if [ -n "$STEAM_COMPAT_TOOL_PATHS" ]; then
    echo "Detected Steam Proton environment."
    # Get the active Proton directory from the environment variable set by Steam
    ACTIVE_PROTON_DIR=$(echo "$STEAM_COMPAT_TOOL_PATHS" | cut -d':' -f1)
    PROTON_PATH="$ACTIVE_PROTON_DIR/proton"

    if ! [[ -f "$PROTON_PATH" && -x "$PROTON_PATH" ]]; then
        notify "Error: Proton executable not found at $PROTON_PATH or not executable. Exiting!"
        exit 1
    fi
else
    echo "Error: This script is intended to be run from Steam with Proton. Exiting!"
    exit 1
fi

debuglog "Using Proton executable at: $PROTON_PATH"

if ! pgrep "$(basename "$LMUSHM_PATH")" > /dev/null; then
    notify "Starting $(basename "$LMUSHM_PATH")..."
    # Feed an open, silent pipe into stdin to make poll() wait instead of loop
    tail -f /dev/null | "$LMUSHM_PATH" &
fi

# Watcher process, this kills lmubridge.exe when the game process closes,
# otherwise wineserver gets stuck and we have to kill it manually.
(
    # Give the game 20 seconds to launch and appear in the process list
    sleep 10
    
    # Loop continuously as long as the game is running
    while pgrep -f "Le Mans Ultimate.exe" > /dev/null; do
        debuglog "Le Mans Ultimate.exe is still running..."
        
        if pgrep -f "$(basename "$LMUBRIDGE_PATH")" > /dev/null; then
            debuglog "$(basename "$LMUBRIDGE_PATH") is still running."
        else
            debuglog "$(basename "$LMUBRIDGE_PATH") is not running, but the game is"
        fi

        if pgrep -f "$(basename "$LMUSHM_PATH")" > /dev/null; then
            debuglog "$(basename "$LMUSHM_PATH") is still running."
        else
            debuglog "$(basename "$LMUSHM_PATH") is not running, but the game is"
        fi
        
        sleep 10
    done
    
    # Once the loop breaks (game closed), kill the bridge to release wineserver
    notify "Game stopped! Closing $(basename "$LMUBRIDGE_PATH")..."
    if pgrep -f "$(basename "$LMUBRIDGE_PATH")" > /dev/null; then
        debuglog "Process $(basename "$LMUBRIDGE_PATH") running, attempting to kill..."
        pkill -f "$(basename "$LMUBRIDGE_PATH")"
        if [ $? -eq 0 ]; then
            notify "Process killed: $(basename "$LMUBRIDGE_PATH")"
        else
            notify "Failed to kill $(basename "$LMUBRIDGE_PATH")"
        fi
    else
        debuglog "$(basename "$LMUBRIDGE_PATH") is not running, no need to kill."
    fi

) &

notify "Starting Le Mans Ultimate..."
debuglog "Using gamemoderun: $(which gamemoderun)"
# Run the game in the foreground to ensure the script waits for it to exit
# before killing the bridge and shared memory processes.
# The bridge will keep wineserver alive until the game exits,
# preventing issues with missing shared memory.
gamemoderun "$@" & sleep 5 && $PROTON_PATH run $LMUBRIDGE_PATH

# Kill the shared memory process
if pgrep "$(basename "$LMUSHM_PATH")" > /dev/null; then
    debuglog "Process $(basename "$LMUSHM_PATH") is running, attempting to kill..."
    pkill "$(basename "$LMUSHM_PATH")"
    if [  $? -eq 0 ]; then
        notify "Process killed: $(basename "$LMUSHM_PATH")"
    else
        notify "Process $(basename "$LMUSHM_PATH") was not running or failed to kill."
    fi
else
    debuglog "Process $(basename "$LMUSHM_PATH") is not running, no need to kill."
fi
