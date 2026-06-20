# Build estático multi-stage. Usa vendor/ para no requerir red en el build.
FROM golang:1.25-alpine AS build
WORKDIR /src
# Dependencias vendoreadas + fuentes + assets embebidos (page.html, logo.png).
COPY go.mod go.sum ./
COPY vendor ./vendor
COPY *.go page.html logo.png ./
RUN CGO_ENABLED=0 go build -mod=vendor -ldflags="-s -w" -o /klip-uploader .

FROM alpine:3.20
RUN adduser -D -u 10001 klip && mkdir -p /var/klip/uploads && chown klip /var/klip/uploads
COPY --from=build /klip-uploader /usr/local/bin/klip-uploader
USER klip
EXPOSE 8080
ENV KLIP_ADDR=0.0.0.0:8080
ENTRYPOINT ["/usr/local/bin/klip-uploader"]
