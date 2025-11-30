#!/bin/bash
#
# Walker/Elephant startup script
# Ensures proper initialization order for the application launcher
#

# Wait for DBus session to be ready
sleep 2

# Ensure XDG directories are set
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Create cache directory if needed
mkdir -p "$XDG_CACHE_HOME"

# Start elephant (application indexer) if not running
if ! pgrep -x elephant >/dev/null; then
    elephant &
    # Give elephant time to start and index
    sleep 3
fi

# Start walker gapplication service
exec walker --gapplication-service
