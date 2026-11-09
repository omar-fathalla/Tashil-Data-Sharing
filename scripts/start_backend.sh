#!/usr/bin/env bash
# Tashil Data Sharing - Backend Lifecycle Helper
# Ensures the Go Cloud Run backend is running and healthy on http://localhost:8080

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend-go"
LOG_FILE="/tmp/tashil_backend.log"

echo "=================================================="
echo "  [Tashil] Checking Go Backend Service (Port 8080) "
echo "=================================================="

# Helper: Forward port 8080 to any connected Android emulator/device
forward_adb_port() {
    local ADB_BIN="$HOME/Library/Android/sdk/platform-tools/adb"
    if [ ! -x "$ADB_BIN" ] && command -v adb >/dev/null 2>&1; then
        ADB_BIN="adb"
    fi
    if [ -x "$ADB_BIN" ] || command -v "$ADB_BIN" >/dev/null 2>&1; then
        "$ADB_BIN" reverse tcp:8080 tcp:8080 2>/dev/null && echo "✓ Android adb port reverse active (tcp:8080 -> host:8080)" || true
    fi
}

# 1. Check if backend is already healthy (/livez: Cloud Run-safe public probe)
if curl -s -f http://localhost:8080/livez > /dev/null 2>&1; then
    echo "✓ Tashil Go Backend is ALREADY running and healthy on http://localhost:8080"
    forward_adb_port
    exit 0
fi

# 2. Check if port 8080 is occupied by a stale or hung process
OCCUPIED_PID=$(lsof -ti :8080 2>/dev/null || true)
if [ -n "$OCCUPIED_PID" ]; then
    echo "⚠️ Port 8080 occupied by PID $OCCUPIED_PID but /livez failed. Terminating stale process..."
    kill -9 $OCCUPIED_PID 2>/dev/null || true
    sleep 1
fi

# 3. Start the Go backend in background
echo "🚀 Starting Go backend (cd backend-go && go run cmd/server/main.go)..."
cd "$BACKEND_DIR" || exit 1
nohup go run cmd/server/main.go > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "Backend process launched (PID: $SERVER_PID). Logging to: $LOG_FILE"

# 4. Wait for /livez to report healthy
echo "Waiting for backend health check..."
for i in {1..30}; do
    if curl -s -f http://localhost:8080/livez > /dev/null 2>&1; then
        echo "✓ Tashil Go Backend is UP and HEALTHY on http://localhost:8080"
        forward_adb_port
        exit 0
    fi

    # Check if server process crashed
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "❌ Server process terminated unexpectedly! Last 20 log lines from $LOG_FILE:"
        tail -n 20 "$LOG_FILE"
        exit 1
    fi

    sleep 0.5
done

echo "⚠️ Backend /livez timed out after 15 seconds. Checking logs:"
tail -n 20 "$LOG_FILE"
exit 0
