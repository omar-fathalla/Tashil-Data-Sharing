#!/usr/bin/env bash
# Tashil Data Sharing - Stop Backend Helper

echo "Stopping Tashil Go Backend on port 8080..."
PIDS=$(lsof -ti :8080 2>/dev/null || true)

if [ -n "$PIDS" ]; then
    echo "Found backend process PID(s): $PIDS"
    kill -15 $PIDS 2>/dev/null || kill -9 $PIDS 2>/dev/null || true
    sleep 1
    if lsof -ti :8080 >/dev/null 2>&1; then
        kill -9 $(lsof -ti :8080) 2>/dev/null || true
    fi
    echo "✓ Tashil Go Backend stopped successfully."
else
    echo "Backend is not running."
fi
