# VPSfacil - Sistema Automatizado de Instalación en VPS

## Descripción del Proyecto

**VPSfacil** es una herramienta automatizada e interactiva para configurar un VPS, diseñada para que usuarios sin conocimientos técnicos de Linux puedan instalar y configurar aplicaciones open source con un solo comando curl.

**Usuario objetivo:** Personas con conocimientos básicos de Linux que quieren desplegar rápidamente un stack completo en su VPS.

---

## Infraestructura

### VPS
- **Proveedor:** Contabo
- **OS:** Debian 12
- **CPU:** 4 cores
- **RAM:** 8 GB
- **Disco:** 75 GB SSD

### Dominio y DNS
- **Dominio de referencia:** `agentexperto.work` (variable, configurable por el usuario)
- **DNS:** Cloudflare (DNS-only, sin CDN/proxy)
- **Propósito:** Crear subdominios para cada aplicación instalada

### Entorno del Cliente
- **OS Local:** Windows 11 Pro 25H2
- **SSH Client:** Bitvise SSH 9.59

---

## Arquitectura de Red: Cloudflare DNS + Tailscale VPN + Let's Encrypt (DNS-01)

**Diseño de máxima seguridad:** Todas las aplicaciones accesibles ÚNICAMENTE vía Tailscale VPN, con URLs HTTPS amigables mediante Let's Encrypt con Cloudflare DNS-01 challenge.

```
┌──────────────────────────────────────────────────────────────┐
│ Navegador: https://n8n.vpn.agentexperto.work                 │
│ (Tailscale VPN debe estar activo)                            │
└──────────────────────────────────────────────────────────────┘
        ↓ Resolución DNS vía Cloudflare (DNS-only, sin proxy)
┌──────────────────────────────────────────────────────────────┐
│ Cloudflare DNS                                               │
│ n8n.vpn.agentexperto.work      → 100.91.x.x (Tailscale IP)  │
│ files.vpn.agentexperto.work    → 100.91.x.x (Tailscale IP)  │
│ openclaw.vpn.agentexperto.work → 100.91.x.x (Tailscale IP)  │
│ portainer.vpn.agentexperto.work→ 100.91.x.x (Tailscale IP)  │
│ kopia.vpn.agentexperto.work    → 100.91.x.x (Tailscale IP)  │
└──────────────────────────────────────────────────────────────┘
        ↓ Túnel VPN Tailscale + cifrado SSL/TLS
┌──────────────────────────────────────────────────────────────┐
│ VPS (IP Tailscale: 100.91.x.x)                               │
│ ├─ Let's Encrypt (wildcard)                             │
│ │  └─ *.vpn.agentexperto.work (renovación automática cada 60 días)              │
│ ├─ N8N          (puerto 5678, solo Tailscale IP)             │
│ ├─ File Browser (puerto 8080, solo Tailscale IP)             │
│ ├─ OpenClaw     (puerto 18789, solo Tailscale IP)            │
│ ├─ Portainer    (puerto 9000, solo Tailscale IP)             │
│ └─ Kopia        (puerto 51515, solo Tailscale IP)            │
└──────────────────────────────────────────────────────────────┘
```

**Ventajas de esta arquitectura:**
- ✅ Cero exposición a internet (100% privado)
- ✅ Sin vulnerabilidad a DDoS
- ✅ URLs HTTPS con nombres DNS amigables y profesionales
- ✅ Certificados SSL válidos (Let's Encrypt, renovación automática)
- ✅ Sin Nginx Proxy Manager (menos componentes, menos mantenimiento)
- ✅ Sin Let's Encrypt (sin renovaciones cada 90 días)
- ✅ Doble cifrado (SSL/TLS + VPN Tailscale)
- ✅ El navegador confía en el certificado (CA de Cloudflare reconocida)
- ✅ Máxima seguridad (acceso solo por VPN)

---

## Configuración Universal: Dominio y Usuario Admin

**VPSfacil es completamente personalizable** — no está atado a ningún dominio o usuario específico.

### Preguntas Iniciales (Primera Ejecución)

Al ejecutar `setup.sh`, se pregunta:

```
[?] Ingresa tu nombre de dominio (ej: example.com):
    agentexperto.work

[?] Ingresa el nombre del usuario admin a crear (ej: admin):
    jaime
```

### Variables Dinámicas

Todos los scripts usan variables, no valores fijos:

```bash
DOMAIN="agentexperto.work"        # Ingresado por el usuario
ADMIN_USER="jaime"                # Ingresado por el usuario

# Derivadas automáticamente:
ADMIN_HOME="/home/${ADMIN_USER}"
APPS_DIR="${ADMIN_HOME}/apps"
CERTS_DIR="${APPS_DIR}/certs"
VPN_SUBDOMAIN="vpn.${DOMAIN}"    # vpn.agentexperto.work
CF_WILDCARD="*.vpn.${DOMAIN}"    # *.vpn.agentexperto.work
```

### Configuración Guardada

Después de la instalación, la configuración se guarda en:
```bash
/home/${ADMIN_USER}/setup.conf
```

Este archivo puede ser cargado (sourced) para re-ejecutar scripts con la misma configuración.

---

## Estructura de Directorios de Aplicaciones

Todas las aplicaciones se instalan bajo `/home/${ADMIN_USER}/apps/`:

```
/home/ADMIN_USER/apps/
├── certs/                      # Certificados SSL (compartidos por todas las apps)
│   ├── origin-cert.pem         # Let's Encrypt (wildcard)
│   ├── origin-cert-key.pem     # Clave privada del certificado
│   └── cloudflare-ca.crt       # CA Bundle de Cloudflare
│
├── portainer/                  # Portainer CE (core, solo VPN)
│   ├── docker-compose.yml
│   ├── .env
│   └── data/
│
├── tailscale/                  # Tailscale (core, túnel VPN)
│   └── (instalado como servicio del sistema, no Docker)
│
├── kopia/                      # Kopia Backup (core, solo VPN)
│   ├── docker-compose.yml
│   ├── .env
│   ├── config/
│   └── cache/
│
├── filebrowser/                # File Browser (core, solo VPN, sin auth)
│   ├── docker-compose.yml
│   └── data/
│
├── n8n/                        # N8N (opcional, solo VPN)
│   ├── docker-compose.yml
│   ├── .env
│   ├── data/
│   └── postgres/               # Base de datos PostgreSQL
│
├── openclaw/                   # OpenClaw (opcional, solo VPN)
│   ├── docker-compose.yml
│   ├── .env
│   ├── config/                 # → /home/node/.openclaw
│   └── data/                   # → /home/node/.openclaw/workspace
│
└── backups/                    # Almacén de backups de Kopia
```

---

## Orden de Instalación (Corregido y Definitivo)

### FASE 1 — Preparación del sistema (como root)

| Script | Descripción |
|--------|-------------|
| `00_precheck.sh` | Verificar OS Debian 12, internet, espacio en disco, instalar dependencias base |
| `01_create_user.sh` | Crear usuario admin, SSH key, agregar a sudo, configurar sudo sin password |
| `02_secure_ssh.sh` | Deshabilitar login root SSH — **PAUSA**: verificar conexión con nuevo usuario |

### FASE 2 — Seguridad base (como admin user)

| Script | Descripción |
|--------|-------------|
| `03_install_firewall.sh` | UFW + fix crítico Docker/UFW (iptables=false), fail2ban |
| `04_install_docker.sh` | Docker CE + Docker Compose v2, agregar usuario a grupo docker |

### FASE 3 — Red privada y certificados (como admin user)

| Script | Descripción |
|--------|-------------|
| `05_install_tailscale.sh` | Instalar Tailscale, autenticar, obtener IP VPN (100.x.x.x) |
| `06_setup_certificates.sh` | Guiar obtención de Let's Encrypt (wildcard), subir al VPS |
| `07_setup_dns.sh` | Crear registros DNS en Cloudflare vía API (*.vpn.DOMAIN → Tailscale IP) |

### FASE 4 — Gestión de contenedores (como admin user)

| Script | Descripción |
|--------|-------------|
| `08_install_portainer.sh` | Portainer CE vía Docker (acceso solo vía VPN) |

### FASE 5 — Backup (como admin user)

| Script | Descripción |
|--------|-------------|
| `09_install_kopia.sh` | Kopia Backup vía Docker, configurar schedule automático |

### FASE 6 — Gestor de archivos (como admin user)

| Script | Descripción |
|--------|-------------|
| `10_install_filebrowser.sh` | File Browser web (gestor de archivos con acceso VPN) |

### FASE 7 — Aplicaciones opcionales (menú interactivo)

| Script | Descripción |
|--------|-------------|
| `apps/n8n.sh` | N8N + PostgreSQL 16 (automatización de flujos) |
| `apps/openclaw.sh` | OpenClaw (asistente IA, solo VPN, credenciales Claude) |

---

## Conflicto Crítico: Docker + UFW

**Problema:** Por defecto, Docker bypasa las reglas de UFW manipulando iptables directamente. Esto deja los puertos de los contenedores expuestos a internet aunque UFW esté activo.

**Solución** (aplicada en `03_install_firewall.sh` ANTES de instalar Docker):

```bash
# /etc/docker/daemon.json
{
  "iptables": false
}
```

Con esto:
- UFW controla todo el tráfico de red
- Docker no manipula iptables
- Las apps solo son accesibles desde la IP de Tailscale (100.x.x.x)
- La IP pública del VPS no expone ningún puerto de aplicación

---

## Mapa de Puertos (Sin Conflictos)

| Puerto | Protocolo | Aplicación | Acceso |
|--------|-----------|------------|--------|
| 22 | TCP | SSH | Internet (temporal, luego solo Tailscale) |
| 41641 | UDP | Tailscale VPN | Internet (WireGuard, requerido) |
| 9000 | TCP | Portainer | Solo Tailscale IP |
| 5678 | TCP | N8N | Solo Tailscale IP |
| 18789 | TCP | OpenClaw WebSocket | Solo Tailscale IP |
| 18790 | TCP | OpenClaw HTTP | Solo Tailscale IP |
| 8080 | TCP | File Browser | Solo Tailscale IP |
| 51515 | TCP | Kopia WebUI | Solo Tailscale IP |

---

## Certificados SSL: Let's Encrypt (wildcard)s

### ¿Por qué son necesarios?
Los navegadores modernos requieren certificados SSL válidos para URLs HTTPS, incluso cuando se accede vía VPN privada.

### Solución: Let's Encrypt (wildcard)s
- **Gratuitos** — sin costo
- **Larga validez** — hasta 15 años (sin renovaciones periódicas)
- **Validación DNS** — validados vía Cloudflare DNS (no requiere acceso público al VPS)
- **Confianza del navegador** — CA de Cloudflare reconocida por todos los navegadores
- **Wildcard** — un solo certificado cubre `*.vpn.DOMAIN`

### Proceso Automatizado en `06_setup_certificates.sh`
1. El script guía al usuario paso a paso en el dashboard de Cloudflare
2. El usuario copia y pega el contenido del certificado en la terminal
3. El script crea los archivos en `/home/${ADMIN_USER}/apps/certs/`
4. Aplica permisos correctos (600 para la clave privada)

### Renovación
- **Años 1-14:** Sin acción requerida
- **Año 14:** Generar nuevo certificado en Cloudflare
- **Año 15:** Copiar nuevo cert al VPS y reiniciar apps

---

## Estructura del Proyecto

```
VPSfacil/
├── CLAUDE.md                        # Documentación del proyecto (este archivo)
├── README.md                        # Guía de usuario
├── setup.sh                         # Script principal (descargado por curl)
├── .gitignore                       # Protege secretos de subir a GitHub
│
├── scripts/                         # Módulos de instalación core
│   ├── 00_precheck.sh               # Verificaciones previas + dependencias
│   ├── 01_create_user.sh            # Crear usuario admin
│   ├── 02_secure_ssh.sh             # Hardening SSH
│   ├── 03_install_firewall.sh       # UFW + fix Docker/UFW
│   ├── 04_install_docker.sh         # Docker CE + Compose v2
│   ├── 05_install_tailscale.sh      # Tailscale VPN
│   ├── 06_setup_certificates.sh     # Let's Encrypt (wildcard)s
│   ├── 07_setup_dns.sh              # DNS Cloudflare vía API
│   ├── 08_install_portainer.sh      # Portainer CE
│   ├── 09_install_kopia.sh          # Kopia Backup
│   └── 10_install_filebrowser.sh    # File Browser web
│
├── apps/                            # Instaladores de aplicaciones opcionales
│   ├── n8n.sh                       # N8N + PostgreSQL
│   └── openclaw.sh                  # OpenClaw IA
│
├── templates/                       # Plantillas Docker Compose
│   ├── n8n/
│   │   └── docker-compose.yml
│   ├── openclaw/
│   │   └── docker-compose.yml
│   ├── portainer/
│   │   └── docker-compose.yml
│   └── kopia/
│       └── docker-compose.yml
│
├── lib/                             # Funciones reutilizables
│   ├── colors.sh                    # Definiciones de colores ANSI
│   ├── utils.sh                     # Utilidades comunes bash
│   ├── config.sh                    # Variables globales y configuración
│   ├── menu.sh                      # Sistema de menú interactivo
│   ├── portainer_api.sh             # Wrappers REST API de Portainer
│   └── cloudflare_api.sh            # Wrappers API DNS de Cloudflare
│
└── config/
    └── defaults.conf                # Puertos, rutas y timeouts por defecto
```

---

## Contexto Crítico: ROOT vs ADMIN_USER

**IMPORTANTE:** Después de crear el usuario admin en `01_create_user.sh`:
- Todas las instalaciones posteriores corren bajo el usuario admin, NO root
- Solo la preparación inicial (precheck, crear usuario, hardening SSH) usa root
- Docker debe ser accesible por el usuario admin (agregado al grupo docker)
- Todos los contenedores son desplegados por el usuario admin
- El acceso SSH al VPS será vía usuario admin después del setup

El usuario admin tiene acceso sudo sin password para permitir pasos de instalación automatizados.

---

## Convenciones de Desarrollo de Scripts

### Interacción con el Usuario

**Cada script debe ser altamente interactivo e informativo:**

1. **Cabeceras de sección claras**
   ```
   ╔════════════════════════════════════════════════════════╗
   ║           Instalando Docker & Docker Compose          ║
   ╚════════════════════════════════════════════════════════╝
   ```

2. **Indicadores de progreso**
   ```
   [✓] Docker instalado correctamente (versión: 24.0.0)
   [⏳] Esperando que el daemon Docker inicie... (60 segundos)
   [✓] Daemon Docker corriendo
   ```

3. **Instrucciones del lado cliente (Windows)**
   ```
   [ℹ] Siguiente paso: Configurar autenticación SSH en tu PC Windows
   [ℹ]
   [ℹ] 1. Abre Bitvise SSH Client
   [ℹ] 2. Ve a: Profile → Authentication
   [ℹ] 3. Importa la clave privada guardada en: C:\Users\TuNombre\jaime_key
   [ℹ] 4. Prueba la conexión a: jaime@tu-vps-ip
   [ℹ]
   [?] Presiona Enter cuando hayas verificado la conexión SSH con el usuario admin...
   ```

4. **Confirmaciones antes de acciones destructivas**
   ```
   [⚠] ADVERTENCIA: Esto deshabilitará el login SSH de root con password
   [⚠] Asegúrate de tener una llave SSH funcionando para el usuario admin
   [?] ¿Continuar? (sí/no):
   ```

5. **Recuperación de errores**
   ```
   [✗] ERROR: El puerto 22 ya está en uso
   [ℹ] Verifica con: sudo netstat -tlnp | grep :22
   [ℹ] Para reintentar, ejecuta este script nuevamente
   ```

### Guía de Estilo Bash
- **Shebang:** `#!/bin/bash`
- **Manejo de errores:** Siempre usar `set -euo pipefail` y trap de errores
- **Logs:** Salida con colores (info, éxito, advertencia, error, prompt)
- **Input de usuario:** Siempre confirmar acciones destructivas
- **Idempotencia:** Scripts seguros de re-ejecutar si algo falla
- **Salida verbose:** Registrar cada paso importante, punto de espera y decisión

### Colores y Output
- **Info:** Azul `[ℹ]`
- **Éxito:** Verde `[✓]`
- **Advertencia:** Amarillo `[⚠]`
- **Error:** Rojo `[✗]`
- **Prompt:** Cian `[?]`
- **Proceso:** Magenta `[⏳]`

### Convención de Carpeta por Aplicación

Cada aplicación en `/home/${ADMIN_USER}/apps/appname/` debe seguir esta estructura:

- `docker-compose.yml` — Especificación del despliegue
- `.env` — Variables de entorno y secretos (creado por el instalador, nunca en git)
- `data/` — Volumen persistente de almacenamiento
- `config/` — Archivos de configuración específicos (si son necesarios)

Todas las rutas persistentes usan rutas relativas: `./data/`, `./config/`

### Funciones Comunes (de `lib/utils.sh`)
- `log_info(mensaje)` — Mensaje informativo en azul
- `log_success(mensaje)` — Mensaje de éxito en verde
- `log_warning(mensaje)` — Advertencia en amarillo
- `log_error(mensaje)` — Error en rojo
- `log_prompt(mensaje)` — Prompt de usuario en cian
- `log_process(mensaje)` — Proceso en curso en magenta
- `confirm(prompt)` — Confirmación S/N
- `wait_for_port(host, port, timeout)` — Health check de puerto
- `ensure_app_dir(appname)` — Crear estructura `/home/${ADMIN_USER}/apps/appname/`
- `source_config()` — Cargar variables globales desde setup.conf
- `check_root()` — Verificar si se ejecuta como root
- `check_not_root()` — Verificar que NO se ejecuta como root

---

## Notas Específicas por Aplicación

### OpenClaw

**Repositorio:** https://github.com/openclaw/openclaw

**Descripción:** Asistente de IA personal que conecta múltiples plataformas de mensajería (WhatsApp, Telegram, Slack, Discord, Google Chat, Signal, iMessage).

**Detalles Docker:**
- **Imagen base:** node:24-bookworm
- **Gestor de paquetes:** pnpm
- **Usuario contenedor:** node (no-root)
- **Entry point:** `node openclaw.mjs gateway --allow-unconfigured`
- **Puertos:** 18789 (WebSocket principal), 18790 (secundario)
- **Health check:** Cada 30 segundos en puerto 18789

**RESTRICCIÓN DE SEGURIDAD: SOLO VPN**

OpenClaw NUNCA debe exponerse a internet público porque:
1. Las credenciales de Claude (session keys, cookies) son extremadamente sensibles
2. La documentación oficial recomienda Tailscale Serve/Funnel para acceso remoto
3. Exponer las credenciales comprometería la cuenta de Claude

**Variables de Entorno Requeridas:**
```
OPENCLAW_GATEWAY_TOKEN          # Token de autenticación del gateway
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=true  # Para despliegue local
CLAUDE_AI_SESSION_KEY           # Credencial Claude AI (SENSIBLE)
CLAUDE_WEB_SESSION_KEY          # Credencial Claude web (SENSIBLE)
CLAUDE_WEB_COOKIE               # Cookie de autenticación Claude (SENSIBLE)
TZ=America/Santiago             # Zona horaria
```

**Almacenamiento Persistente:**
```
./config/ → /home/node/.openclaw
./data/   → /home/node/.openclaw/workspace
```

**Permisos del .env:** 600 (solo lectura del propietario)

### N8N

**Imagen:** docker.n8n.io/n8nio/n8n:latest
**Puerto interno:** 5678
**Base de datos:** PostgreSQL 16 (contenedor separado en la misma compose)
**Variables clave:** DB_TYPE, DB_POSTGRESDB_*, N8N_ENCRYPTION_KEY, WEBHOOK_URL

### File Browser

**Imagen:** filebrowser/filebrowser:latest
**Puerto interno:** 8080
**Volúmenes:** ./config (base de datos SQLite), ./data (archivos del servidor)
**Sin base de datos externa** (usa SQLite interno)

---

## Seguridad

1. **SSH:** Login root con password deshabilitado después de crear usuario admin
2. **Firewall:** UFW habilitado con reglas restrictivas por defecto
3. **Docker/UFW:** `iptables: false` en daemon.json para evitar bypass de UFW
4. **Secretos:** Contraseñas/tokens vía variables de entorno, nunca en scripts
5. **Certificados:** Clave privada con permisos 600
6. **Cloudflare:** Tokens API en `.env`, nunca en git
7. **Backups:** Kopia configurado con storage encriptado
8. **OpenClaw:** Nunca exponer a internet, siempre solo VPN

---

## GitHub y Control de Versiones

- **Repositorio:** https://github.com/JaimeCruzH/vpsfacil
- **Rama principal:** main
- **Archivos protegidos por .gitignore:** *.env, *.pem, *.key, *.crt, setup.conf, backups/

---

## Estado del Proyecto

- [x] Arquitectura definida
- [x] Estructura de carpetas creada
- [x] CLAUDE.md actualizado
- [x] GitHub configurado
- [ ] Scripts en desarrollo

**Próximo paso:** Escribir scripts comenzando por `lib/colors.sh` → `lib/utils.sh` → `setup.sh` → scripts en orden 00-09 → apps opcionales.
