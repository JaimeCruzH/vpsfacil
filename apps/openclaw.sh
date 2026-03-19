#!/bin/bash
# ============================================================
# apps/openclaw.sh — Instalar OpenClaw (Asistente IA)
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Advierte sobre la sensibilidad de las credenciales
#   2. Guía al usuario para obtener credenciales de Claude
#   3. Despliega OpenClaw vía Docker
#   4. Configura acceso SOLO vía Tailscale VPN
#
# SEGURIDAD: OpenClaw NUNCA debe exponerse a internet.
# Las credenciales de Claude son extremadamente sensibles.
#
# Repositorio: https://github.com/openclaw/openclaw
# Imagen base: node:24-bookworm
# Acceso: http://openclaw.vpn.DOMAIN:18789 (solo Tailscale VPN)
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/portainer_api.sh"
source_config

# ============================================================
print_header "App Opcional — Instalar OpenClaw"
# ============================================================

check_root

log_info "OpenClaw es un asistente de IA personal que conecta"
log_info "WhatsApp, Telegram, Slack, Discord y más plataformas."
echo ""

# ============================================================
# ADVERTENCIA DE SEGURIDAD CRÍTICA
# ============================================================
echo ""
echo -e "${COLOR_BOLD_RED}╔══ ADVERTENCIA DE SEGURIDAD CRÍTICA ════════════════════════╗${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║  OpenClaw requiere tus credenciales personales de Claude.  ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║  Estas credenciales dan acceso completo a tu cuenta.       ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║  Por eso OpenClaw NUNCA se expone a internet.              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║  Solo accesible vía Tailscale VPN (red privada).           ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║  Las credenciales se guardarán en:                         ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║  ${APPS_DIR}/openclaw/.env (permisos 600)         ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}║                                                            ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_RED}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
echo ""

if ! confirm "¿Entiendes los riesgos y deseas continuar?"; then
    log_info "Instalación cancelada."
    exit 0
fi

check_docker || { log_error "Docker no está instalado."; exit 1; }

# ============================================================
# 1. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

APP_DIR="${APPS_DIR}/openclaw"
mkdir -p "${APP_DIR}/config"
mkdir -p "${APP_DIR}/data"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
log_success "Directorio: ${APP_DIR} ✓"

# ============================================================
# 2. OBTENER CREDENCIALES DE CLAUDE
# ============================================================
log_step "Configurar credenciales de Claude"

echo ""
log_info "Necesitas obtener tus credenciales de sesión de Claude."
log_info "Estas se obtienen desde el navegador cuando estás logueado."
echo ""

windows_instruction "CÓMO OBTENER LAS CREDENCIALES DE CLAUDE

1. Abre Chrome o Edge en Windows

2. Ve a: https://claude.ai y asegúrate de estar logueado

3. Presiona F12 para abrir las DevTools

4. Ve a la pestaña: Application (o Aplicación)

5. En el panel izquierdo: Storage → Cookies → https://claude.ai

6. Busca y copia los siguientes valores:
   - sessionKey: empieza con 'sk-ant-sid...'
   - __Secure-next-auth.session-token (puede ser largo)

7. También necesitas:
   - En Network tab: busca una petición a claude.ai
   - Copia el valor del header 'Cookie' completo

ALTERNATIVA MÁS FÁCIL: Usa la extensión 'EditThisCookie' de Chrome
para exportar todas las cookies de claude.ai en formato JSON."

echo ""
wait_for_user "Presiona Enter cuando tengas las credenciales listas..."

# Pedir credenciales
echo ""
log_warning "Las credenciales NO se mostrarán mientras las escribes."
echo ""

CLAUDE_AI_SESSION_KEY=$(prompt_password "Pega el sessionKey de Claude AI (sk-ant-sid...)")
echo ""
CLAUDE_WEB_SESSION_KEY=$(prompt_password "Pega el __Secure-next-auth.session-token")
echo ""
log_info "Ahora pega el contenido del header Cookie completo de claude.ai"
log_info "Termina con ENTER + CTRL+D:"
echo ""
CLAUDE_WEB_COOKIE=""
while IFS= read -r linea; do
    linea="${linea//$'\r'/}"  # strip CRLF artifacts
    CLAUDE_WEB_COOKIE+="${linea}"
done

# Validaciones básicas
if [[ -z "$CLAUDE_AI_SESSION_KEY" ]]; then
    log_error "La session key de Claude no puede estar vacía"
    exit 1
fi

# ============================================================
# 3. GENERAR TOKEN DE GATEWAY
# ============================================================
log_step "Generando token de Gateway de OpenClaw"

GATEWAY_TOKEN=$(generate_token 32)
log_success "Token de Gateway generado ✓"

# ============================================================
# 4. CREAR ARCHIVO .ENV
# ============================================================
log_step "Guardando configuración"

cat > "${APP_DIR}/.env" << EOF
# OpenClaw — VPSfacil
# CONFIDENCIAL — NO compartir ni subir a GitHub
# Permisos: 600 (solo lectura del propietario)

OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=true

CLAUDE_AI_SESSION_KEY=${CLAUDE_AI_SESSION_KEY}
CLAUDE_WEB_SESSION_KEY=${CLAUDE_WEB_SESSION_KEY}
CLAUDE_WEB_COOKIE=${CLAUDE_WEB_COOKIE}

TZ=${TIMEZONE}
EOF

chmod 600 "${APP_DIR}/.env"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"
log_success "Archivo .env creado con permisos 600 ✓"

# ============================================================
# 5. CREAR DOCKERFILE PERSONALIZADO
# ============================================================
log_step "Preparando imagen Docker de OpenClaw"

cat > "${APP_DIR}/Dockerfile" << 'EOF'
FROM node:24-bookworm

# Instalar pnpm
RUN npm install -g pnpm

# Instalar OpenClaw globalmente
RUN pnpm add -g openclaw@latest

# Usuario no-root
USER node
WORKDIR /home/node

EXPOSE 18789 18790

CMD ["node", "/usr/local/lib/node_modules/openclaw/openclaw.mjs", "gateway", "--allow-unconfigured"]
EOF

chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/Dockerfile"

# ============================================================
# 6. CONSTRUIR IMAGEN DOCKER
# ============================================================
log_step "Construyendo imagen Docker de OpenClaw"

cd "$APP_DIR"
log_process "Construyendo imagen (puede tardar 3-5 minutos la primera vez)..."
docker build -t openclaw-vpsfacil:latest . 2>&1 | tail -10

log_success "Imagen openclaw-vpsfacil:latest construida ✓"

# ============================================================
# 7. PREPARAR Y DESPLEGAR VÍA PORTAINER
# ============================================================
log_step "Generando docker-compose.yml"

COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# OpenClaw — VPSfacil
# Acceso: http://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_WS}
# SOLO vía Tailscale VPN — NUNCA exponer a internet
# ============================================================
services:
  openclaw:
    image: openclaw-vpsfacil:latest
    container_name: openclaw
    restart: unless-stopped
    environment:
      HOME: /home/node
      TERM: xterm
      TZ: ${TIMEZONE}
      OPENCLAW_GATEWAY_TOKEN: ${GATEWAY_TOKEN}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: "true"
      CLAUDE_AI_SESSION_KEY: ${CLAUDE_AI_SESSION_KEY}
      CLAUDE_WEB_SESSION_KEY: ${CLAUDE_WEB_SESSION_KEY}
      CLAUDE_WEB_COOKIE: ${CLAUDE_WEB_COOKIE}
    ports:
      - "${PORT_OPENCLAW_WS}:18789"
      - "${PORT_OPENCLAW_HTTP}:18790"
    volumes:
      - ${APP_DIR}/config:/home/node/.openclaw
      - ${APP_DIR}/data:/home/node/.openclaw/workspace
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "18789"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks:
      - vpsfacil-net

networks:
  vpsfacil-net:
    external: true
EOF
)

# Guardar docker-compose.yml de referencia
echo "$COMPOSE_CONTENT" > "${APP_DIR}/docker-compose.yml"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/docker-compose.yml"
log_success "docker-compose.yml generado ✓"

log_step "Desplegando OpenClaw via Portainer"

log_process "Registrando stack en Portainer..."
if portainer_deploy_stack "openclaw" "$COMPOSE_CONTENT"; then
    log_process "Levantando contenedor..."
else
    log_warning "Portainer no disponible. Desplegando con docker compose directamente..."
    cd "$APP_DIR"
    docker compose up -d
fi

log_process "Esperando que OpenClaw inicie..."
wait_for_port "localhost" "${PORT_OPENCLAW_WS}" "${TIMEOUT_APP_START}"

log_success "OpenClaw está corriendo ✓"

# ============================================================
# INSTRUCCIONES DE CONFIGURACIÓN
# ============================================================
echo ""
windows_instruction "CONFIGURACIÓN INICIAL DE OPENCLAW

OpenClaw necesita configuración adicional en el servidor.

1. En tu sesión SSH, ejecuta:
   docker exec -it openclaw node openclaw.mjs onboard

2. Sigue el asistente interactivo para:
   - Conectar plataformas de mensajería (WhatsApp, Telegram, etc.)
   - Configurar las skills disponibles
   - Ajustar políticas de privacidad

3. Para acceder a la interfaz web:
   URL: http://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_WS}
   Token: ${GATEWAY_TOKEN}

IMPORTANTE: Usa HTTP (no HTTPS) — OpenClaw usa su propio
protocolo WebSocket y no necesita certificado SSL externo."

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "OpenClaw instalado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso:${COLOR_RESET}"
echo -e "    URL:          ${COLOR_CYAN}http://openclaw.vpn.${DOMAIN}:${PORT_OPENCLAW_WS}${COLOR_RESET}"
echo -e "    Token:        ${COLOR_CYAN}${GATEWAY_TOKEN}${COLOR_RESET}"
echo -e "    Acceso:       ${COLOR_BOLD_RED}SOLO con Tailscale VPN activo${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Seguridad:${COLOR_RESET}"
echo -e "    .env:         ${COLOR_GREEN}Permisos 600 (solo ${ADMIN_USER})${COLOR_RESET}"
echo -e "    Internet:     ${COLOR_RED}SIN exposición pública${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
echo ""
