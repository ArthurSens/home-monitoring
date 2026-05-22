OCB_VERSION ?= v0.152.1
OTELCOL_BUILDER_CONFIG := opentelemetry-collector/builder-config.yaml
OTELCOL_BUILD_DIR := opentelemetry-collector/_build

.PHONY: otelcol-generate
otelcol-generate:
	go run go.opentelemetry.io/collector/cmd/builder@$(OCB_VERSION) --config=$(OTELCOL_BUILDER_CONFIG) --skip-compilation

.PHONY: otelcol-build
otelcol-build:
	go run go.opentelemetry.io/collector/cmd/builder@$(OCB_VERSION) --config=$(OTELCOL_BUILDER_CONFIG)

.PHONY: otelcol-check
otelcol-check: otelcol-generate
	cd $(OTELCOL_BUILD_DIR) && go build ./...

.PHONY: otelcol-image
otelcol-image:
	docker compose build otel-collector

.PHONY: otelcol-clean
otelcol-clean:
	rm -rf $(OTELCOL_BUILD_DIR)
