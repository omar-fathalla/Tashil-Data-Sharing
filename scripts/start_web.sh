#!/usr/bin/env bash
# Tashil Data Sharing - Web Frontend Lifecycle Helper
# Launches the Flutter Web application on a predictable, fixed port (http://localhost:3000)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/tashil_web"
PORT=3000
LOG_FILE="/tmp/tashil_web.log"

echo "=================================================="
echo "  [Tashil] Checking Flutter Web Service (Port $PORT)"
echo "=================================================="

# 1. Check if already responding
if curl -s -f "http://localhost:$PORT/index.html" > /dev/null 2>&1; then
    echo "✓ Tashil Flutter Web is ALREADY running on http://localhost:$PORT"
    open "http://localhost:$PORT"
    exit 0
fi

# 2. Check if port is occupied by a stale or hung process
OCCUPIED_PID=$(lsof -ti :$PORT 2>/dev/null || true)
if [ -n "$OCCUPIED_PID" ]; then
    echo "⚠️ Port $PORT occupied by PID $OCCUPIED_PID. Freeing port..."
    kill -9 $OCCUPIED_PID 2>/dev/null || true
    sleep 1
fi

# 3. Start Flutter Web Server in background
echo "🚀 Starting Flutter Web Server (flutter run -d web-server --web-port=$PORT --web-hostname=localhost)..."
cd "$WEB_DIR" || exit 1
> "$LOG_FILE"
nohup flutter run -d web-server --web-port=$PORT --web-hostname=localhost > "$LOG_FILE" 2>&1 &
FLUTTER_PID=$!
echo "Flutter process launched (PID: $FLUTTER_PID). Logging to: $LOG_FILE"

# 4. Wait for web server to start responding
echo "Waiting for Flutter Web to compile and serve..."
for i in {1..60}; do
    if curl -s "http://localhost:$PORT/index.html" | grep -q "Tashil" 2>/dev/null; then
        echo "✓ Tashil Flutter Web is UP and SERVING on http://localhost:$PORT"
        open "http://localhost:$PORT"
        exit 0
    fi

    # Check if process crashed
    if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
        echo "❌ Flutter process terminated unexpectedly! Last 25 log lines:"
        tail -n 25 "$LOG_FILE"
        exit 1
    fi

    sleep 1
done

echo "⚠️ Timed out waiting for Flutter Web. Last 25 log lines from $LOG_FILE:"
tail -n 25 "$LOG_FILE"
exit 0
