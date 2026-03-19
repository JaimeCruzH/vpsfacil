#!/bin/bash
# ============================================================
# apps/filebrowser.sh — Instalar File Browser
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea estructura de directorios para File Browser
#   2. Despliega File Browser vía Docker con HTTPS
#   3. Muestra instrucciones para el primer acceso
#
# Credenciales por defecto: admin / admin
# El usuario las cambia desde la interfaz web.
#
# Acceso: https://files.vpn.DOMAIN:8080 (solo Tailscale VPN)
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
print_header "App Opcional — Instalar File Browser"
# ============================================================

check_root

log_info "File Browser es un gestor de archivos web que permite"
log_info "ver, editar, subir y descargar archivos del servidor"
log_info "desde tu navegador con una interfaz moderna."
echo ""
log_info "Tendrás acceso a: ${APPS_DIR}/"
log_info "Acceso: ${URL_FILEBROWSER}"
log_info "(requiere Tailscale VPN activo)"
echo ""

check_docker || { log_error "Docker no está instalado."; exit 1; }

if [[ ! -f "${CERT_FILE}" || ! -f "${CERT_KEY}" ]]; then
    log_error "Certificados SSL no encontrados. Ejecuta el paso 7 primero."
    exit 1
fi

# ============================================================
# 1. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

APP_DIR="${APPS_DIR}/filebrowser"
mkdir -p "${APP_DIR}/config"
mkdir -p "${APP_DIR}/data"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
log_success "Directorio: ${APP_DIR} ✓"

# ============================================================
# 2. CREAR CONFIGURACIÓN DE FILE BROWSER
# ============================================================
log_step "Creando configuración"

cat > "${APP_DIR}/config/filebrowser.json" << EOF
{
  "port": 8080,
  "baseURL": "",
  "address": "0.0.0.0",
  "log": "stdout",
  "database": "/config/filebrowser.db",
  "root": "/srv",
  "cert": "/certs/cert.pem",
  "key": "/certs/key.pem",
  "noAuth": false
}
EOF

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/config"
log_success "Configuración creada ✓"

# ============================================================
# 3. PREPARAR Y DESPLEGAR VÍA PORTAINER
# ============================================================
log_step "Generando docker-compose.yml"

COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# File Browser — VPSfacil
# Acceso: https://files.vpn.${DOMAIN}:${PORT_FILEBROWSER}
# Solo vía Tailscale VPN
# Credenciales por defecto: admin / admin
# ============================================================
services:
  filebrowser:
    image: ${IMG_FILEBROWSER}
    container_name: filebrowser
    restart: unless-stopped
    user: "0:0"
    environment:
      TZ: ${TIMEZONE}
    ports:
      - "${PORT_FILEBROWSER}:8080"
    volumes:
      - ${APP_DIR}/config:/config
      - ${APP_DIR}/data:/srv/local
      - ${APPS_DIR}:/srv/apps
      - ${ADMIN_HOME}:/srv/home:ro
      - ${CERT_FILE}:/certs/cert.pem:ro
      - ${CERT_KEY}:/certs/key.pem:ro
    command: --config /config/filebrowser.json
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
# 4. DESPLEGAR
# ============================================================
log_step "Desplegando File Browser via Portainer"

log_process "Registrando stack en Portainer..."
if portainer_deploy_stack "filebrowser" "$COMPOSE_CONTENT"; then
    log_process "Descargando imagen y levantando contenedor..."
else
    log_warning "Portainer no disponible. Desplegando con docker compose directamente..."
    cd "$APP_DIR"
    docker compose pull 2>&1 | tail -3
    docker compose up -d
fi

log_process "Esperando que File Browser inicie..."
wait_for_port "localhost" "${PORT_FILEBROWSER}" 60

log_success "File Browser está corriendo ✓"

# ============================================================
# INSTRUCCIONES DE PRIMER ACCESO
# ============================================================
echo ""
windows_instruction "PRIMER ACCESO A FILE BROWSER

1. Activa Tailscale VPN en Windows

2. Abre tu navegador y ve a:
   ${URL_FILEBROWSER}

3. Ingresa las credenciales por defecto:
   Usuario:    admin
   Contraseña: admin

4. Para cambiar usuario y contraseña (recomendado):
   → Haz clic en tu nombre (arriba a la derecha)
   → Selecciona 'User Management'
   → Edita el usuario admin: cambia nombre y contraseña
   → Guarda los cambios

5. Tendrás acceso a:
   /apps   → Todas las aplicaciones instaladas
   /home   → Directorio home de ${ADMIN_USER} (solo lectura)
   /local  → Almacenamiento local de File Browser"

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "File Browser instalado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso:${COLOR_RESET}"
echo -e "    URL:          ${COLOR_CYAN}${URL_FILEBROWSER}${COLOR_RESET}"
echo -e "    Usuario:      ${COLOR_CYAN}admin${COLOR_RESET}"
echo -e "    Contraseña:   ${COLOR_CYAN}admin${COLOR_RESET} (cambia desde la interfaz web)"
echo -e "    Acceso:       ${COLOR_YELLOW}Solo con Tailscale VPN activo${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Carpetas accesibles:${COLOR_RESET}"
echo -e "    /apps  → ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
echo -e "    /home  → ${COLOR_CYAN}${ADMIN_HOME}${COLOR_RESET} (solo lectura)"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
echo ""
