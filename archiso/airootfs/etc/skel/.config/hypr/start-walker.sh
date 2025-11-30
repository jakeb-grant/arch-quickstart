#!/bin/bash
#
# Walker/Elephant startup script
# Ensures proper initialization order for the application launcher
#

# Wait for DBus session to be ready
sleep 2

# Explicitly set XDG directories with all standard paths
# This ensures Elephant can find .desktop files
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_DATA_DIRS="$XDG_DATA_HOME:/usr/local/share:/usr/share:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Create necessary directories
mkdir -p "$XDG_CACHE_HOME"
mkdir -p "$XDG_DATA_HOME/applications"

# Kill any existing elephant to ensure clean start
pkill -x elephant 2>/dev/null || true
sleep 1

# Start elephant with explicit paths
elephant &
ELEPHANT_PID=$!

# Give elephant time to start and index applications
sleep 5

# Verify elephant is running
if ! kill -0 $ELEPHANT_PID 2>/dev/null; then
    echo "Warning: Elephant failed to start" >&2
fi

# Start walker gapplication service
exec walker --gapplication-service
