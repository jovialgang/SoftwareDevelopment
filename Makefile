.PHONY: run tidy run-all run-prometheus run-grafana stop install-tools

# Путь к homebrew-префиксу (для run-prometheus / run-grafana по отдельности).
BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /usr/local)

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
	@lsof -ti:8080 | xargs kill 2>/dev/null || true
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
	@mkdir -p data/grafana
	@bash -c '\
		P="$(PWD)"; \
		GF_PATHS_PROVISIONING="$$P/configs/grafana/provisioning" \
		GF_PATHS_DATA="$$P/data/grafana" \
		GF_SERVER_HTTP_PORT=3000 \
		GF_AUTH_ANONYMOUS_ENABLED=true \
		GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
		GF_SECURITY_ADMIN_PASSWORD=admin \
		GF_DASHBOARD_PATH="$$P/configs/grafana/dashboards" \
		grafana server --homepath "$(BREW_PREFIX)/share/grafana"'

# ─────────────────────────────────────────────
# Установка инструментов (macOS + Homebrew)
# ─────────────────────────────────────────────

install-tools:
	brew install prometheus grafana
