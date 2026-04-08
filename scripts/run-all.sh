#!/usr/bin/env bash
set -euo pipefail

# Абсолютный путь к корню проекта
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALLOY_BIN="/opt/homebrew/opt/alloy/bin/alloy"
if [ ! -x "$ALLOY_BIN" ]; then
    ALLOY_BIN="/usr/local/opt/alloy/bin/alloy"
fi
if [ ! -x "$ALLOY_BIN" ]; then
    ALLOY_BIN="alloy"
fi

GRAFANA_HOME="/opt/homebrew/share/grafana"
if [ ! -d "$GRAFANA_HOME" ]; then
    GRAFANA_HOME="/usr/local/share/grafana"
fi

mkdir -p "$PROJECT_DIR/data/prometheus" "$PROJECT_DIR/data/grafana"
mkdir -p "$PROJECT_DIR/data/loki" "$PROJECT_DIR/data/alloy" "$PROJECT_DIR/data/logs"
mkdir -p "$PROJECT_DIR/data/grafana/plugins"
mkdir -p "$PROJECT_DIR/configs/grafana/provisioning/plugins" "$PROJECT_DIR/configs/grafana/provisioning/alerting"
: > "$PROJECT_DIR/data/logs/app.log"

# Освобождаем порты если остались процессы от предыдущего запуска.
echo "▶ Освобождаем порты 8080, 9090, 3000, 3100, 12345 ..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:9090 | xargs kill -9 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:3100 | xargs kill -9 2>/dev/null || true
lsof -ti:12345 | xargs kill -9 2>/dev/null || true
sleep 1

# Prometheus
echo "▶ Запуск Prometheus на http://localhost:9090 ..."
prometheus \
    --config.file="$PROJECT_DIR/configs/prometheus.yml" \
    --storage.tsdb.path="$PROJECT_DIR/data/prometheus" \
    --web.listen-address=:9090 &
PROM_PID=$!

# Loki
echo "▶ Запуск Loki на http://localhost:3100 ..."
loki \
    -config.file="$PROJECT_DIR/configs/loki.yml" &
LOKI_PID=$!

# Alloy
echo "▶ Запуск Alloy на http://localhost:12345 ..."
"$ALLOY_BIN" run \
    --storage.path="$PROJECT_DIR/data/alloy" \
    "$PROJECT_DIR/configs/alloy.config" &
ALLOY_PID=$!

# Grafana
echo "▶ Запуск Grafana на http://localhost:3000 (admin/admin) ..."
GF_PATHS_PROVISIONING="$PROJECT_DIR/configs/grafana/provisioning" \
GF_PATHS_DATA="$PROJECT_DIR/data/grafana" \
GF_PATHS_PLUGINS="$PROJECT_DIR/data/grafana/plugins" \
GF_SERVER_HTTP_PORT=3000 \
GF_SECURITY_ADMIN_PASSWORD=admin \
GF_DASHBOARD_PATH="$PROJECT_DIR/configs/grafana/dashboards" \
grafana server --homepath "$GRAFANA_HOME" &
GRAFANA_PID=$!

# Остановка по Ctrl-C / завершению скрипта
cleanup() {
    echo ""
    echo "▶ Останавливаем Prometheus, Grafana, Loki и Alloy..."
    kill "$PROM_PID" "$GRAFANA_PID" "$LOKI_PID" "$ALLOY_PID" 2>/dev/null || true
    wait "$PROM_PID" "$GRAFANA_PID" "$LOKI_PID" "$ALLOY_PID" 2>/dev/null || true
    echo "✓ Стек остановлен."
}
trap cleanup EXIT INT TERM

# Приложение (foreground)
echo "▶ Запуск приложения на http://localhost:8080 ..."
cd "$PROJECT_DIR"
go run ./cmd/server 2>&1 | tee -a "$PROJECT_DIR/data/logs/app.log"
