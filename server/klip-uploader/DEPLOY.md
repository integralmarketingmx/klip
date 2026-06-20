# klip-uploader — despliegue (POC estilo Lightshot)

Servicio de subida de capturas que devuelve un link público corto, con auto-purga a 3 días.

## Dónde está desplegado

- **VPS**: `31.220.31.197` (`srv1093926`, Ubuntu 24.04, Hostinger KVM 2, EasyPanel + Traefik).
- **URL pública**: `https://klip.p0wzj8.easypanel.host` (wildcard de EasyPanel, TLS Let's Encrypt automático).
- **Acceso**: SSH por llave `root@31.220.31.197` (credenciales/panel en 1Password: item "EasyPanel").

## Arquitectura

El VPS corre **EasyPanel con Traefik** (file provider), Traefik ya tiene 80/443. **No se usa Caddy**
(chocaría). El uploader es un contenedor Docker en la red `easypanel`, y Traefik lo enruta vía una
ruta en `custom.yaml`. Las imágenes viven en `/var/klip/uploads` (bind-mount al host) y un systemd
timer las purga a los 3 días.

```
Cliente (app Klip) --POST /upload--> Traefik(443) --> contenedor klip-uploader:8080 --> /var/klip/uploads
                                                          |
                                  GET /slug.png <---------+  (file server del propio Go)
```

## Componentes

| Pieza | Ubicación |
|---|---|
| Código Go | `/opt/klip-uploader/{main.go,go.mod,Dockerfile}` |
| Imagen | `klip-uploader:latest` (docker) |
| Contenedor | `klip-uploader` (red `easypanel`, restart unless-stopped) |
| Ruta Traefik | `/etc/easypanel/traefik/config/custom.yaml` |
| Uploads | `/var/klip/uploads` (host, uid 10001) |
| Purga 3 días | `/etc/systemd/system/klip-purge.{service,timer}` (hourly) |

## Re-deploy (tras cambiar main.go)

```bash
scp main.go root@31.220.31.197:/opt/klip-uploader/
ssh root@31.220.31.197 'cd /opt/klip-uploader && docker build -t klip-uploader:latest . && \
  docker rm -f klip-uploader; \
  docker run -d --name klip-uploader --restart unless-stopped --network easypanel \
    -e KLIP_BASE_URL=https://klip.p0wzj8.easypanel.host -e KLIP_ADDR=0.0.0.0:8080 \
    -v /var/klip/uploads:/var/klip/uploads klip-uploader:latest'
```

## API

- `POST /upload` — multipart, campo `file`. Devuelve `{"url":"https://klip.p0wzj8.easypanel.host/<slug>.png"}`.
- `GET /<slug>.png` — sirve la imagen (Cache-Control 3 días).
- `GET /health` — `ok`.
- Límite: 25 MB por archivo. Slug: 6 chars base58 (sin caracteres ambiguos).

## Probado

```
$ curl -F "file=@shot.png" https://klip.p0wzj8.easypanel.host/upload
{"url":"https://klip.p0wzj8.easypanel.host/hwrniu.png"}
$ curl -I https://klip.p0wzj8.easypanel.host/hwrniu.png   # HTTP 200 image/png
```

## INBOX por MX propio (Sprint 4)

Receptor SMTP que recibe respuestas a `klip+<slug>@<dominio>`, las correlaciona por slug
y las guarda como `<slug>.replies.json` (+ imágenes `<slug>.reply-N.png`) en `uploadDir`.
El endpoint `GET /inbox` fusiona estas respuestas con las leídas por Gmail (DWD), dedupe por `msgId`.

### Env vars

| Env | Default | Descripción |
|---|---|---|
| `KLIP_MX_DOMAIN` | (vacío) | Dominio que recibe el MX (p.ej. `klip.integralmarketing.agency`). **Si está vacío, el receptor SMTP NO arranca** (no rompe el deploy actual). |
| `KLIP_SMTP_ADDR` | `:25` | Dirección de escucha del receptor SMTP. |

Correlación de slug (orden de confianza): (1) destinatario `klip+<slug>@`, (2) header
`In-Reply-To`/`References` con el Message-ID determinista `<klip-<slug>@…>`, (3) token
`[klip#<slug>]` en el asunto (case-insensitive, tolera `Re:/RE:/Fwd:`). Sin auth (recepción
entrante de MX), límite 25 MB, sin TLS obligatorio. Destinatarios fuera de patrón → 550.

### Retención

`deploy/klip-purge.sh` ya respeta los hilos abiertos: si existe `<slug>.replies.json`, el
slug **no se purga** (ni imagen ni derivados).

### Pasos de infra que faltan para activarlo

1. **DNS MX**: crear registro `MX` del dominio elegido (p.ej. `klip.integralmarketing.agency`)
   apuntando al host del VPS (`31.220.31.197`), prioridad 10. Además un `A` del host del MX.
2. **Puerto 25 entrante**: abrir TCP/25 en el firewall del VPS/Hostinger y exponerlo al
   contenedor (`-p 25:25` o `-e KLIP_SMTP_ADDR=0.0.0.0:25` + `EXPOSE 25` en el run de docker).
   Nota: muchos proveedores cloud bloquean el 25 entrante por defecto; verificar con Hostinger.
3. **Arranque**: relanzar el contenedor agregando `-e KLIP_MX_DOMAIN=klip.integralmarketing.agency`
   (y opcional `-e KLIP_SMTP_ADDR=0.0.0.0:25`) al `docker run`.
4. **Reverse DNS / SPF (opcional, anti-spam)**: PTR del IP y SPF del dominio para que las
   respuestas no se marquen como spam si algún MTA hace checks salientes.

## Notas

- `Caddyfile.snippet` y `deploy/klip-uploader.service` quedan como referencia para un despliegue
  alternativo en un VPS SIN EasyPanel (binario en el host + Caddy). NO es lo desplegado aquí.
- Para revertir: `docker rm -f klip-uploader`, vaciar `custom.yaml`, `systemctl disable --now klip-purge.timer`.
