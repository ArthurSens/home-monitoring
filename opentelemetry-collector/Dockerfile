FROM golang:1.26.5-bookworm@sha256:1a15e02ae3cdabf9cc5b7e6ef1de3e3a1933ddccbb082cdb67f6922c02d7e6d0 AS builder

ARG OCB_VERSION=v0.156.0

WORKDIR /src

COPY opentelemetry-collector/builder-config.yaml opentelemetry-collector/builder-config.yaml

RUN go install go.opentelemetry.io/collector/cmd/builder@${OCB_VERSION}
RUN builder --config=opentelemetry-collector/builder-config.yaml

FROM gcr.io/distroless/base-debian12:nonroot@sha256:4b5196599229a5cf312a676cfe1ee8587ecf2371dcc22620f8c7a66d77d125c8

COPY --from=builder /src/opentelemetry-collector/_build/home-monitoring-otelcol /home-monitoring-otelcol

ENTRYPOINT ["/home-monitoring-otelcol"]
