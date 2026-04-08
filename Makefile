.PHONY: run tidy run-all run-prometheus run-grafana run-loki run-alloy stop install-tools

# ─────────────────────────────────────────────
# Разработка
# ─────────────────────────────────────────────

run:
	go run ./cmd/server

tidy:
	go mod tidy

# ─────────────────────────────────────────────
# Полный стек: приложение + Prometheus + Grafana
# ─────────────────────────────────────────────

## run-all: запускает весь стек. Ctrl-C останавливает всё сразу.
run-all:
	@bash scripts/run-all.sh

## stop: принудительная остановка всего стека.
stop:
	@pkill -f "prometheus --config.file" 2>/dev/null || true
	@pkill -f "grafana server" 2>/dev/null || true
	@pkill -f "loki -config.file" 2>/dev/null || true
	@pkill -f "alloy run" 2>/dev/null || true
	@lsof -ti:8080 | xargs kill 2>/dev/null || true
	@lsof -ti:3100 | xargs kill 2>/dev/null || true
	@lsof -ti:12345 | xargs kill 2>/dev/null || true
	@echo "✓ Стек остановлен."

# ─────────────────────────────────────────────
# Запуск сервисов по отдельности
# ─────────────────────────────────────────────

run-prometheus:
	@mkdir -p data/prometheus
	prometheus \
		--config.file=configs/prometheus.yml \
		--storage.tsdb.path=./data/prometheus \
		--web.listen-address=:9090

run-grafana:
	@mkdir -p data/grafana data/grafana/plugins configs/grafana/provisioning/plugins configs/grafana/provisioning/alerting
	@bash -c '\
		GRAFANA_HOME="/opt/homebrew/share/grafana"; \
		if [ ! -d "$$GRAFANA_HOME" ]; then GRAFANA_HOME="/usr/local/share/grafana"; fi; \
		if [ ! -d "$$GRAFANA_HOME" ]; then echo "✗ Не найден homepath Grafana"; exit 1; fi; \
		P="$(PWD)"; \
		GF_PATHS_PROVISIONING="$$P/configs/grafana/provisioning" \
		GF_PATHS_DATA="$$P/data/grafana" \
		GF_PATHS_PLUGINS="$$P/data/grafana/plugins" \
		GF_SERVER_HTTP_PORT=3000 \
		GF_SECURITY_ADMIN_PASSWORD=admin \
		GF_DASHBOARD_PATH="$$P/configs/grafana/dashboards" \
		grafana server --homepath "$$GRAFANA_HOME"'

run-loki:
	@mkdir -p data/loki
	loki -config.file=configs/loki.yml

run-alloy:
	@mkdir -p data/logs data/alloy
	@bash -c '\
		ALLOY_BIN=""; \
		if command -v grafana-alloy >/dev/null 2>&1; then ALLOY_BIN="$$(command -v grafana-alloy)"; \
		elif [ -x "/opt/homebrew/opt/alloy/bin/alloy" ]; then ALLOY_BIN="/opt/homebrew/opt/alloy/bin/alloy"; \
		elif [ -x "/usr/local/opt/alloy/bin/alloy" ]; then ALLOY_BIN="/usr/local/opt/alloy/bin/alloy"; \
		fi; \
		if [ -z "$$ALLOY_BIN" ]; then \
			echo "✗ Grafana Alloy не найден. Установите: brew tap grafana/grafana && brew install grafana/grafana/alloy"; \
			exit 1; \
		fi; \
		"$$ALLOY_BIN" run --storage.path=./data/alloy configs/alloy.config'

# ─────────────────────────────────────────────
# Установка инструментов (macOS + Homebrew)
# ─────────────────────────────────────────────

install-tools:
	brew tap grafana/grafana
	brew install prometheus grafana loki grafana/grafana/alloy
