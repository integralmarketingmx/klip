# Build estático multi-stage (sin dependencias externas).
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /klip-uploader .

FROM alpine:3.20
RUN adduser -D -u 10001 klip && mkdir -p /var/klip/uploads && chown klip /var/klip/uploads
COPY --from=build /klip-uploader /usr/local/bin/klip-uploader
USER klip
EXPOSE 8080
ENV KLIP_ADDR=0.0.0.0:8080
ENTRYPOINT ["/usr/local/bin/klip-uploader"]
