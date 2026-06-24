FROM golang:1.26.4-bookworm@sha256:d16a600dd352dd9a1bd0d262aaef18dba17b02a758cdba1069cf3ae1aad93fa5 AS builder

ARG OCB_VERSION=v0.155.0

WORKDIR /src

COPY opentelemetry-collector/builder-config.yaml opentelemetry-collector/builder-config.yaml

RUN go install go.opentelemetry.io/collector/cmd/builder@${OCB_VERSION}
RUN builder --config=opentelemetry-collector/builder-config.yaml

FROM gcr.io/distroless/base-debian12:nonroot@sha256:7a75a36f4bec82a7542c64195e402907486f9a4dd2f8797a976aa0cf31cfb470

COPY --from=builder /src/opentelemetry-collector/_build/home-monitoring-otelcol /home-monitoring-otelcol

ENTRYPOINT ["/home-monitoring-otelcol"]
