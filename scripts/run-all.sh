#!/usr/bin/env bash
set -euo pipefail

# Абсолютный путь к корню проекта
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPO_DOCKER_CONFIG="/tmp/mini-task-tracker-tempo.yml"
TEMPO_DOCKER_IMAGE="grafana/tempo:2.9.0"

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
mkdir -p "$PROJECT_DIR/data/loki" "$PROJECT_DIR/data/tempo" "$PROJECT_DIR/data/alloy" "$PROJECT_DIR/data/logs"
mkdir -p "$PROJECT_DIR/data/grafana/plugins"
mkdir -p "$PROJECT_DIR/configs/grafana/provisioning/plugins" "$PROJECT_DIR/configs/grafana/provisioning/alerting"
: > "$PROJECT_DIR/data/logs/app.log"

# Освобождаем порты если остались процессы от предыдущего запуска.
echo "▶ Освобождаем порты 8080, 9090, 3000, 3100, 3200, 4317, 12345, 14317 ..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:9090 | xargs kill -9 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:3100 | xargs kill -9 2>/dev/null || true
lsof -ti:3200 | xargs kill -9 2>/dev/null || true
lsof -ti:4317 | xargs kill -9 2>/dev/null || true
lsof -ti:12345 | xargs kill -9 2>/dev/null || true
lsof -ti:14317 | xargs kill -9 2>/dev/null || true
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

# Tempo
echo "▶ Запуск Tempo на http://localhost:3200 ..."
if command -v tempo >/dev/null 2>&1; then
    tempo -config.file="$PROJECT_DIR/configs/tempo.yml" &
    TEMPO_PID=$!
elif docker info >/dev/null 2>&1; then
    cp "$PROJECT_DIR/configs/tempo.yml" "$TEMPO_DOCKER_CONFIG"
    docker rm -f mini-task-tracker-tempo >/dev/null 2>&1 || true
    docker run --rm --name mini-task-tracker-tempo \
        -p 3200:3200 -p 4317:4317 \
        -v "$TEMPO_DOCKER_CONFIG:/etc/tempo/tempo.yml:ro" \
        "$TEMPO_DOCKER_IMAGE" -config.file=/etc/tempo/tempo.yml &
    TEMPO_PID=$!
else
    echo "✗ Не найден бинарник tempo и Docker недоступен."
    echo "  Установите Tempo: brew install grafana/grafana/tempo"
    echo "  Или запустите Docker Desktop и повторите make run-all."
    exit 1
fi

# Ждём готовности Tempo, иначе Alloy будет бесконечно ретраить экспорт трейсов.
for i in {1..90}; do
    if curl -fsS "http://localhost:3200/ready" >/dev/null 2>&1; then
        echo "✓ Tempo готов."
        break
    fi
    if [ "$i" -eq 90 ]; then
        echo "✗ Tempo не стал ready за 90 секунд."
        echo "  Посмотрите логи: docker logs mini-task-tracker-tempo --tail 100"
        exit 1
    fi
    sleep 1
done

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
    echo "▶ Останавливаем Prometheus, Grafana, Loki, Tempo и Alloy..."
    docker stop mini-task-tracker-tempo >/dev/null 2>&1 || true
    kill "$PROM_PID" "$GRAFANA_PID" "$LOKI_PID" "$TEMPO_PID" "$ALLOY_PID" 2>/dev/null || true
    wait "$PROM_PID" "$GRAFANA_PID" "$LOKI_PID" "$TEMPO_PID" "$ALLOY_PID" 2>/dev/null || true
    echo "✓ Стек остановлен."
}
trap cleanup EXIT INT TERM

# Приложение (foreground)
echo "▶ Запуск приложения на http://localhost:8080 ..."
cd "$PROJECT_DIR"
go run ./cmd/server 2>&1 | tee -a "$PROJECT_DIR/data/logs/app.log"
