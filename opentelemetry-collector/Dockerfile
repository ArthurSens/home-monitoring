FROM golang:1.26.5-bookworm@sha256:349ad04971da5f200a537641ae2c70774a592ca21fad4b513b65f813f546781a AS builder

ARG OCB_VERSION=v0.156.0

WORKDIR /src

COPY opentelemetry-collector/builder-config.yaml opentelemetry-collector/builder-config.yaml

RUN go install go.opentelemetry.io/collector/cmd/builder@${OCB_VERSION}
RUN builder --config=opentelemetry-collector/builder-config.yaml

FROM gcr.io/distroless/base-debian12:nonroot@sha256:6c806311d31c11d364a8d13a022af5a48f29e43bd585ad6b51f1bb447f83d239

COPY --from=builder /src/opentelemetry-collector/_build/home-monitoring-otelcol /home-monitoring-otelcol

ENTRYPOINT ["/home-monitoring-otelcol"]
