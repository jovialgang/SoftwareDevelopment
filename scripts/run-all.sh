#!/usr/bin/env bash
set -euo pipefail

# Абсолютный путь к корню проекта - работает даже если путь содержит пробелы.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$PROJECT_DIR/data/prometheus" "$PROJECT_DIR/data/grafana"

# Освобождаем порты если остались процессы от предыдущего запуска.
echo "▶ Освобождаем порты 8080, 9090, 3000 ..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:9090 | xargs kill -9 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
sleep 1

# Prometheus
echo "▶ Запуск Prometheus на http://localhost:9090 ..."
prometheus \
    --config.file="$PROJECT_DIR/configs/prometheus.yml" \
    --storage.tsdb.path="$PROJECT_DIR/data/prometheus" \
    --web.listen-address=:9090 &
PROM_PID=$!

# Grafana
echo "▶ Запуск Grafana на http://localhost:3000 (admin/admin) ..."
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /usr/local)"
GF_PATHS_PROVISIONING="$PROJECT_DIR/configs/grafana/provisioning" \
GF_PATHS_DATA="$PROJECT_DIR/data/grafana" \
GF_SERVER_HTTP_PORT=3000 \
GF_AUTH_ANONYMOUS_ENABLED=true \
GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
GF_SECURITY_ADMIN_PASSWORD=admin \
GF_DASHBOARD_PATH="$PROJECT_DIR/configs/grafana/dashboards" \
grafana server --homepath "$BREW_PREFIX/share/grafana" &
GRAFANA_PID=$!

# Остановка по Ctrl-C / завершению скрипта
cleanup() {
    echo ""
    echo "▶ Останавливаем Prometheus и Grafana..."
    kill "$PROM_PID" "$GRAFANA_PID" 2>/dev/null || true
    wait "$PROM_PID" "$GRAFANA_PID" 2>/dev/null || true
    echo "✓ Стек остановлен."
}
trap cleanup EXIT INT TERM

# Приложение (foreground)
echo "▶ Запуск приложения на http://localhost:8080 ..."
cd "$PROJECT_DIR"
go run ./cmd/server
