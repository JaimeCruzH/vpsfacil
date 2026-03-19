#!/bin/bash
# ============================================================
# apps/filebrowser.sh — Instalar File Browser
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Acceso: https://files.vpn.DOMAIN:8080 (solo Tailscale VPN)
# Credenciales por defecto: admin / admin
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
log_info "Acceso: ${URL_FILEBROWSER}"
log_info "(requiere Tailscale VPN activo)"
echo ""

check_docker || { log_error "Docker no está instalado."; exit 1; }

APP_DIR="${APPS_DIR}/filebrowser"

# ============================================================
# 1. LIMPIAR INSTALACIÓN ANTERIOR
# ============================================================
log_step "Preparando instalación limpia"

# Detener y eliminar contenedor anterior
if docker ps -aq --filter "name=filebrowser" 2>/dev/null | grep -q .; then
    log_process "Deteniendo contenedor anterior..."
    docker stop filebrowser 2>/dev/null || true
    docker rm   filebrowser 2>/dev/null || true
    log_success "Contenedor anterior eliminado ✓"
fi

# Eliminar base de datos para que arranque con admin/admin
if [[ -f "${APP_DIR}/filebrowser.db" ]]; then
    rm -f "${APP_DIR}/filebrowser.db"
    log_success "Base de datos limpiada ✓"
fi

# ============================================================
# 2. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

mkdir -p "${APP_DIR}/data"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
log_success "Directorio: ${APP_DIR} ✓"

# ============================================================
# 3. PREPARAR Y DESPLEGAR VÍA PORTAINER
# ============================================================
log_step "Generando docker-compose.yml"

# La base de datos se monta directamente como archivo en /database.db
# (ubicación por defecto del contenedor oficial de File Browser)
COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# File Browser — VPSfacil
# Acceso: http://files.vpn.${DOMAIN}:${PORT_FILEBROWSER}
# Solo vía Tailscale VPN — Credenciales: admin / admin
# Nota: HTTP es seguro porque Tailscale cifra todo el tráfico
#       con WireGuard (no se necesita SSL adicional)
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
      - ${APP_DIR}/filebrowser.db:/database.db
      - ${APP_DIR}/data:/srv/local
      - ${APPS_DIR}:/srv/apps
      - ${ADMIN_HOME}:/srv/home:ro
    command: >
      --database /database.db
      --root /srv
      --address 0.0.0.0
      --port 8080
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

# Crear archivo vacío para la base de datos ANTES de montar
# (evita que Docker lo cree como directorio)
touch "${APP_DIR}/filebrowser.db"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/filebrowser.db"

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
   (nota: usa http:// no https://)

3. Ingresa las credenciales por defecto:
   Usuario:    admin
   Contraseña: admin

4. Para cambiar usuario y contraseña (recomendado):
   → Haz clic en el ícono de persona (arriba a la derecha)
   → Selecciona 'User Management'
   → Edita el usuario admin
   → Cambia nombre y contraseña → Guarda

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
echo -e "    Contraseña:   ${COLOR_CYAN}admin${COLOR_RESET}  ← cambia desde la interfaz web"
echo -e "    Acceso:       ${COLOR_YELLOW}Solo con Tailscale VPN activo${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Carpetas accesibles:${COLOR_RESET}"
echo -e "    /apps  → ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
echo -e "    /home  → ${COLOR_CYAN}${ADMIN_HOME}${COLOR_RESET} (solo lectura)"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
echo ""
