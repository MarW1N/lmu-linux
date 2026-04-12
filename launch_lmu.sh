#!/bin/bash

# This script is designed to launch Le Mans Ultimate
# with the LMU Shared Memory Bridge (lmubridge.exe)
# and the shared memory process (lmushm) on Linux using Proton.
# It also includes optimizations for better performance
# and a simple notification system to track the launch process.
# Launch LMU from Steam with these launch options:
#
# /path/to/launch_lmu.sh %command%

# Set the path to the LMU Shared Memory Bridge and shared memory executable
# Put environment variables in lmu.env in the same directory as this script
SIMSHMBRIDGE_PATH="${HOME}/Apps/simshmbridge/bin"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LMU_ENV_FILE="${SCRIPT_PATH}/lmu.env"

notify() {
    echo "[$(date +'%T')] $1" >> "$LOG_FILE"
    if [ -n "$DISPLAY" ]; then
        notify-send -a "LMU" -t 1000 "$1"
    fi
}

# Read environment variables from the lmu.env file if it exists
if [ -f "$LMU_ENV_FILE" ]; then
    set -a                 # Automatically export all variables defined after this point
    source "$LMU_ENV_FILE"     # Read the variables
    set +a                 # Stop automatically exporting
fi

LMU_BRIDGE="${SIMSHMBRIDGE_PATH}/lmubridge.exe"
LMUSHM="${SIMSHMBRIDGE_PATH}/lmushm"
LOG_FILE="/tmp/lmu_launch.log"

if [ -n "$STEAM_COMPAT_TOOL_PATHS" ]; then
    echo "Detected Steam Proton environment."
    # Get the active Proton directory from the environment variable set by Steam
    ACTIVE_PROTON_DIR=$(echo "$STEAM_COMPAT_TOOL_PATHS" | cut -d':' -f1)
    PROTON_CMD="$ACTIVE_PROTON_DIR/proton"
else
    echo "Error: This script is intended to be run from Steam with Proton. Exiting!"
    exit 1
fi

# Clean up old log file if it exists
if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE"
fi

if ! pgrep "lmushm" > /dev/null; then
    notify "Starting lmushm..."
    "$LMUSHM" &
fi

# Start the bridge in the background, it will run until the game process closes.
# We have to do this before launching the game to ensure the shared memory
# is available when the game starts.
# The bridge will also keep wineserver alive until the game exits,
# preventing issues with missing shared memory.
(
    sleep 5
    notify "Starting lmubridge.exe..."
    
    "$PROTON_CMD" run "$LMUBRIDGE" 2>&1
    
    notify "Process lmubridge.exe has exited."
) &

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
    notify "Game stopped! Closing lmubridge.exe..."
    pkill -f "lmubridge.exe"
) &

notify "Starting Le Mans Ultimate..."
# Run the game in the foreground to ensure the script waits for it to exit
# before killing the bridge and shared memory processes.
# The bridge will keep wineserver alive until the game exits,
# preventing issues with missing shared memory.
gamemoderun "$@" & sleep 5 && $PROTON_CMD run $LMU_BRIDGE

# Kill the shared memory process
notify "Killing process lmushm..."
pkill "lmushm"

