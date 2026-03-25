.PHONY: run tidy run-all run-prometheus run-grafana install-tools

# Путь к homebrew-префиксу (работает на Apple Silicon и Intel Mac).
BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /usr/local)
# Директория с dashboard JSON-файлами (нужна Grafana для provisioning).
DASHBOARD_PATH := $(PWD)/configs/grafana/dashboards

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

## run-all: запускает Prometheus и Grafana в фоне, затем поднимает приложение на переднем плане.
## Ctrl-C останавливает приложение; Prometheus и Grafana продолжат работу — остановить их можно через `make stop`.
run-all:
	@mkdir -p data/prometheus data/grafana
	@echo "▶ Запуск Prometheus на http://localhost:9090 ..."
	prometheus \
		--config.file=configs/prometheus.yml \
		--storage.tsdb.path=./data/prometheus \
		--web.listen-address=:9090 &
	@echo "▶ Запуск Grafana на http://localhost:3000 (admin/admin) ..."
	GF_PATHS_PROVISIONING=$(PWD)/configs/grafana/provisioning \
	GF_PATHS_DATA=$(PWD)/data/grafana \
	GF_SERVER_HTTP_PORT=3000 \
	GF_AUTH_ANONYMOUS_ENABLED=true \
	GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
	GF_SECURITY_ADMIN_PASSWORD=admin \
	GF_DASHBOARD_PATH=$(DASHBOARD_PATH) \
	grafana server --homepath "$(BREW_PREFIX)/share/grafana" &
	@echo "▶ Запуск приложения на http://localhost:8080 ..."
	go run ./cmd/server

## stop: останавливает Prometheus и Grafana.
stop:
	@pkill -f "prometheus --config.file=configs/prometheus.yml" 2>/dev/null || true
	@pkill -f "grafana server" 2>/dev/null || true
	@echo "✓ Prometheus и Grafana остановлены."

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
	@mkdir -p data/grafana
	GF_PATHS_PROVISIONING=$(PWD)/configs/grafana/provisioning \
	GF_PATHS_DATA=$(PWD)/data/grafana \
	GF_SERVER_HTTP_PORT=3000 \
	GF_AUTH_ANONYMOUS_ENABLED=true \
	GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
	GF_SECURITY_ADMIN_PASSWORD=admin \
	GF_DASHBOARD_PATH=$(DASHBOARD_PATH) \
	grafana server --homepath "$(BREW_PREFIX)/share/grafana"

# ─────────────────────────────────────────────
# Установка инструментов (macOS + Homebrew)
# ─────────────────────────────────────────────

install-tools:
	brew install prometheus grafana
