#!/bin/bash

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
LAUNCH_LMU_ENV_FILE="${SCRIPT_PATH}/launch_lmu.env"
[ -f "$LAUNCH_LMU_ENV_FILE" ] || { echo "Warning: Environment file $LAUNCH_LMU_ENV_FILE not found. Exiting!" >> "$LOG_FILE"; exit 1; }
LOG_FILE="${SCRIPT_PATH}/launch_lmu.log"

notify() {
    echo "[$(date +'%T')] $1" >> "$LOG_FILE"
    if [ -n "$DISPLAY" ]; then
        notify-send -a "LMU" -t 1000 "$1"
    fi
}

# Read environment variables from the lmu.env file if it exists
if [ -f "$LAUNCH_LMU_ENV_FILE" ]; then
    set -a                 # Automatically export all variables defined after this point
    source "$LAUNCH_LMU_ENV_FILE"     # Read the variables
    set +a                 # Stop automatically exporting
fi

LMUBRIDGE_PATH="${SIMSHMBRIDGE_PATH}/lmubridge.exe"
[ -f "$LMUBRIDGE_PATH" ] || { echo "Error: LMU Bridge executable not found at $LMUBRIDGE_PATH. Exiting!" >> "$LOG_FILE"; exit 1; }
LMUSHM_PATH="${SIMSHMBRIDGE_PATH}/lmushm"
[ -f "$LMUSHM_PATH" ] || { echo "Error: LMU Shared Memory executable not found at $LMUSHM_PATH. Exiting!" >> "$LOG_FILE"; exit 1; }

if [ -n "$STEAM_COMPAT_TOOL_PATHS" ]; then
    echo "Detected Steam Proton environment."
    # Get the active Proton directory from the environment variable set by Steam
    ACTIVE_PROTON_DIR=$(echo "$STEAM_COMPAT_TOOL_PATHS" | cut -d':' -f1)
    PROTON_PATH="$ACTIVE_PROTON_DIR/proton"
else
    echo "Error: This script is intended to be run from Steam with Proton. Exiting!"
    exit 1
fi

# Clean up old log file if it exists
if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE"
fi

if ! pgrep "$(basename "$LMUSHM_PATH")" > /dev/null; then
    notify "Starting $(basename "$LMUSHM_PATH")..."
    "$LMUSHM_PATH" &
fi

# Start the bridge in the background, it will run until the game process closes.
# We have to do this before launching the game to ensure the shared memory
# is available when the game starts.
# The bridge will also keep wineserver alive until the game exits,
# preventing issues with missing shared memory.
#(
#    sleep 5
#    notify "Starting $(basename "$LMUBRIDGE_PATH")..."
#    
#    "$PROTON_PATH" run "$LMUBRIDGE_PATH" 2>&1
#    
#    notify "Process $(basename "$LMUBRIDGE_PATH") has exited."
#) &

# watcher process, this kills lmubridge.exe when the game process closes,
# otherwise wineserver gets stuck and we have to kill it manually.
(
    # Give the game 20 seconds to launch and appear in the process list
    sleep 10
    
    # Loop continuously as long as the game is running
    while pgrep -f "Le Mans Ultimate.exe" > /dev/null; do
        sleep 10
    done
    
    # Once the loop breaks (game closed), kill the bridge to release wineserver
    notify "Game stopped! Closing $(basename "$LMUBRIDGE_PATH")..."
    pkill -f "$(basename "$LMUBRIDGE_PATH")"
) &

notify "Starting Le Mans Ultimate..."
# Run the game in the foreground to ensure the script waits for it to exit
# before killing the bridge and shared memory processes.
# The bridge will keep wineserver alive until the game exits,
# preventing issues with missing shared memory.
gamemoderun "$@" & sleep 5 && $PROTON_PATH run $LMUBRIDGE_PATH

# Kill the shared memory process
notify "Killing process $(basename "$LMUSHM_PATH")..."
pkill "$(basename "$LMUSHM_PATH")"

