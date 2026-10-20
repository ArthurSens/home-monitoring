FROM golang:1.27.3-bookworm@sha256:5c3e9b43cfd3bb95c7937462e29d87ada57b481a96fa23ad0eb61778d7a00110 AS builder

ARG OCB_VERSION=v0.163.0

WORKDIR /src

COPY opentelemetry-collector/builder-config.yaml opentelemetry-collector/builder-config.yaml

RUN go install go.opentelemetry.io/collector/cmd/builder@${OCB_VERSION}
RUN builder --config=opentelemetry-collector/builder-config.yaml

FROM gcr.io/distroless/base-debian12:nonroot@sha256:7f0c72cd138b442ae0deeb69c08b1acf5525439ba251a49ad93c320a061567e5

COPY --from=builder /src/opentelemetry-collector/_build/home-monitoring-otelcol /home-monitoring-otelcol

ENTRYPOINT ["/home-monitoring-otelcol"]
