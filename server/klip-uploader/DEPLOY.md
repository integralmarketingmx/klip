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

## Notas

- `Caddyfile.snippet` y `deploy/klip-uploader.service` quedan como referencia para un despliegue
  alternativo en un VPS SIN EasyPanel (binario en el host + Caddy). NO es lo desplegado aquí.
- Para revertir: `docker rm -f klip-uploader`, vaciar `custom.yaml`, `systemctl disable --now klip-purge.timer`.
