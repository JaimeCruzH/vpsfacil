# VPSfacil - Sistema Automatizado de Instalación en VPS

**VPSfacil** es una herramienta interactiva y automatizada para configurar un VPS con Debian 12, diseñada para desplegar un stack completo de aplicaciones con un solo comando.

## Inicio Rápido

### Requisitos
- VPS con Debian 12 (recomendado: Contabo)
- Acceso SSH como root
- Dominio propio con DNS en Cloudflare
- PC Windows con Bitvise SSH Client

### Comando de instalación

Ejecutar en el VPS:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main/install.sh)
```

O desde archivo local:

```bash
bash setup.sh
```

## Qué se instala

### Aplicaciones Core (pasos 1-12)

| App | Puerto | Acceso |
|-----|--------|--------|
| Portainer CE | 9443 (HTTPS) | Solo VPN Tailscale |
| Kopia Backup | 51515 (HTTPS) | Solo VPN Tailscale |
| File Browser | 8080 (HTTP) | Solo VPN Tailscale |
| Beszel Hub | 8090 (HTTP) | Solo VPN Tailscale |

### Aplicaciones Opcionales

| App | Puerto | Notas |
|-----|--------|-------|
| N8N | 5678 (HTTPS) | + PostgreSQL 16, ejecutar `bash apps/n8n.sh` |

## Arquitectura de Red

Todas las aplicaciones son accesibles **únicamente vía Tailscale VPN**, con HTTPS válido (Let's Encrypt wildcard):

```
Navegador (Tailscale activo)
    → DNS Cloudflare: portainer.vpn.DOMAIN → 100.x.x.x (IP Tailscale)
    → Túnel WireGuard cifrado
    → VPS: contenedores escuchan solo en IP Tailscale
```

- **Sin exposición a internet** — máxima seguridad
- **HTTPS válido** — Let's Encrypt wildcard `*.vpn.DOMAIN` vía DNS-01
- **Sin Nginx Proxy Manager** — menos componentes, menos mantenimiento

## Estructura de Directorios

Todas las apps se instalan bajo `/home/ADMIN_USER/apps/`:

```
/home/ADMIN_USER/apps/
├── certs/          # Certificados SSL wildcard (compartidos)
├── portainer/      # Portainer CE (gestión Docker)
├── kopia/          # Kopia Backup (backups automáticos)
├── filebrowser/    # File Browser web
├── beszel/         # Beszel Monitoring
├── n8n/            # N8N Automatización (opcional)
│   └── postgres/   # Base de datos PostgreSQL
└── backups/        # Almacén de backups de Kopia
```

Cada carpeta de app contiene:
- `docker-compose.yml` — Configuración del servicio
- `.env` — Variables y secretos (nunca en git)
- `data/` — Volumen persistente

## Características Principales

### Instalación Interactiva
- Guía paso a paso con prompts claros
- Instrucciones para servidor (VPS) y cliente (Windows)
- Mensajes con código de colores (Info, Éxito, Advertencia, Error)
- Confirmación antes de acciones destructivas

### Seguridad
- Autenticación SSH por llave (sin passwords)
- UFW con reglas restrictivas + fix Docker/UFW (`iptables: false`)
- Todo accesible solo por VPN Tailscale
- Backups automáticos con Kopia

### Recuperación de Instalación

Si se interrumpe la instalación, el progreso se guarda automáticamente. Al reconectar y re-ejecutar `setup.sh`, el sistema detecta el avance y ofrece continuar desde donde se detuvo.

## Después de la Instalación

### Acceso a las Aplicaciones

Todas las URLs siguen el patrón `*.vpn.DOMAIN` (requiere Tailscale activo):

- Portainer: `https://portainer.vpn.DOMAIN:9443`
- Kopia: `https://kopia.vpn.DOMAIN:51515`
- File Browser: `http://files.vpn.DOMAIN:8080`
- Beszel: `http://beszel.vpn.DOMAIN:8090`
- N8N (opcional): `https://n8n.vpn.DOMAIN:5678`

### Acceso SSH

```bash
ssh -i /ruta/a/llave_privada ADMIN_USER@IP_VPS
```

### Gestión de Aplicaciones

```bash
# Ver logs de una app
cd /home/ADMIN_USER/apps/appname
docker compose logs -f

# Reiniciar una app
docker compose restart

# Detener una app
docker compose down

# Iniciar una app
docker compose up -d
```

## Solución de Problemas

### Puerto en uso
```bash
sudo netstat -tlnp | grep :PUERTO
```

### Docker no responde
```bash
sudo systemctl restart docker
```

### Certificados SSL expirados
```bash
sudo certbot renew
```

---

Para documentación técnica detallada, ver [CLAUDE.md](./CLAUDE.md)

**Target OS:** Debian 12 | **Última actualización:** 2026-05-13
