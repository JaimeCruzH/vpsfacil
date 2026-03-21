#!/bin/bash
# ============================================================
# scripts/11_install_beszel.sh — Instalar Beszel Monitoring (Hub)
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Despliega Beszel Hub (dashboard de monitoreo, puerto 8090)
#
# El agent se instala manualmente después desde el dashboard.
#
# Beszel monitorea: CPU, RAM, disco, red, temperatura, contenedores
#
# Acceso web: http://beszel.vpn.DOMAIN:8090 (solo Tailscale VPN)
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ ! -f "${LIB_DIR}/colors.sh" ]] 2>/dev/null; then
    SCRIPT_DIR=""
fi

if [[ -z "$SCRIPT_DIR" ]] || [[ ! -f "${LIB_DIR}/colors.sh" ]]; then
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    LIB_DIR="/tmp/vpsfacil_lib_$$"
    mkdir -p "$LIB_DIR"
    curl -sSL "${REPO_RAW}/lib/colors.sh"  -o "${LIB_DIR}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh"  -o "${LIB_DIR}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh"   -o "${LIB_DIR}/utils.sh"
    curl -sSL "${REPO_RAW}/lib/portainer_api.sh" -o "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true
fi

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config
source "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true

# ============================================================
print_header "Paso 11 de 12 — Instalar Beszel Monitoring"
# ============================================================

check_root

log_info "Beszel es un sistema de monitoreo ligero que muestra"
log_info "CPU, RAM, disco, red, temperatura y estado de contenedores"
log_info "desde un dashboard web."
echo ""
log_info "Acceso: ${URL_BESZEL}"
log_info "(requiere Tailscale VPN activo)"
echo ""

check_docker || { log_error "Docker no está instalado."; exit 1; }

APP_DIR="${APPS_DIR}/beszel"

# ============================================================
# 1. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

mkdir -p "${APP_DIR}/beszel_data"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"

log_success "Directorio: ${APP_DIR} ✓"

# ============================================================
# 2. GENERAR DOCKER-COMPOSE (solo Hub)
# ============================================================
log_step "Generando configuración de Beszel Hub"

COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# Beszel Monitoring Hub — VPSfacil
# Dashboard: http://beszel.vpn.${DOMAIN}:${PORT_BESZEL}
# Solo vía Tailscale VPN
#
# El agent se configura después desde el dashboard de Beszel.
# ============================================================
services:
  beszel-hub:
    image: ${IMG_BESZEL}
    container_name: beszel
    restart: unless-stopped
    ports:
      - "${PORT_BESZEL}:8090"
    volumes:
      - ${APP_DIR}/beszel_data:/beszel_data
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - vpsfacil-net

networks:
  vpsfacil-net:
    external: true
EOF
)

echo "$COMPOSE_CONTENT" > "${APP_DIR}/docker-compose.yml"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/docker-compose.yml"
log_success "docker-compose.yml generado ✓"

# ============================================================
# 3. DESPLEGAR BESZEL HUB
# ============================================================
log_step "Desplegando Beszel Hub"

# Detener contenedor anterior si existe
docker stop beszel 2>/dev/null || true
docker rm beszel 2>/dev/null || true

log_process "Registrando stack en Portainer..."
if portainer_deploy_stack "beszel" "$COMPOSE_CONTENT" 2>/dev/null; then
    log_success "Stack creado en Portainer ✓"
else
    log_warning "Portainer no disponible. Desplegando con docker compose directamente..."
    cd "$APP_DIR"
    docker compose pull 2>&1 | tail -5
    docker compose up -d
fi

log_process "Esperando que Beszel Hub inicie..."
wait_for_port "localhost" "${PORT_BESZEL}" 60

log_success "Beszel Hub corriendo ✓"

# ============================================================
# 4. GUARDAR CONFIGURACIÓN
# ============================================================
log_step "Guardando configuración"

cat > "${APP_DIR}/.env" << EOF
# Beszel Monitoring — VPSfacil
BESZEL_HUB_PORT=${PORT_BESZEL}
EOF

chmod 600 "${APP_DIR}/.env"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"

log_success "Configuración guardada ✓"

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "Beszel Hub instalado exitosamente"
echo ""
log_info "Las instrucciones de acceso se mostrarán al final de la instalación."
echo ""
