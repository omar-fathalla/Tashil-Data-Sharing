#!/usr/bin/env bash
# Tashil Data Sharing - Stop Web Frontend Service
PORT=3000
echo "Stopping Tashil Web on port $PORT..."
PIDS=$(lsof -ti :$PORT 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "Found web process PID(s): $PIDS"
    kill -9 $PIDS 2>/dev/null || true
    echo "✓ Tashil Web stopped successfully."
else
    echo "No process running on port $PORT."
fi
