#!/bin/bash
# ============================================================
# apps/filebrowser.sh — Instalar File Browser
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea estructura de directorios para File Browser
#   2. Configura acceso al directorio /apps/ del servidor
#   3. Despliega File Browser vía Docker con HTTPS
#   4. Configura usuario admin con contraseña segura
#
# File Browser permite explorar y gestionar archivos del
# servidor desde el navegador con interfaz amigable.
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
# 2. CONFIGURAR USUARIO ADMIN
# ============================================================
log_step "Configuración del usuario administrador"

echo ""
FB_USER=$(prompt_input "Nombre de usuario para File Browser" "${ADMIN_USER}")

while true; do
    FB_PASS=$(prompt_password "Contraseña para File Browser")
    FB_PASS2=$(prompt_password "Confirma la contraseña")
    if [[ "$FB_PASS" == "$FB_PASS2" && ${#FB_PASS} -ge 8 ]]; then
        break
    elif [[ "$FB_PASS" != "$FB_PASS2" ]]; then
        log_warning "Las contraseñas no coinciden."
    else
        log_warning "Mínimo 8 caracteres."
    fi
done

# ============================================================
# 3. CREAR ARCHIVO .ENV
# ============================================================
cat > "${APP_DIR}/.env" << EOF
# File Browser — VPSfacil
FB_USER=${FB_USER}
FB_PASS=${FB_PASS}
TZ=${TIMEZONE}
EOF

chmod 600 "${APP_DIR}/.env"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"
log_success "Credenciales guardadas ✓"

# ============================================================
# 4. CREAR CONFIGURACIÓN DE FILE BROWSER
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

# ============================================================
# 5. PREPARAR Y DESPLEGAR VÍA PORTAINER
# ============================================================
log_step "Generando docker-compose.yml"

COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# File Browser — VPSfacil
# Acceso: https://files.vpn.${DOMAIN}:${PORT_FILEBROWSER}
# Solo vía Tailscale VPN
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

# Guardar docker-compose.yml de referencia
echo "$COMPOSE_CONTENT" > "${APP_DIR}/docker-compose.yml"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/docker-compose.yml"
log_success "docker-compose.yml generado ✓"

# ============================================================
# 6. DESPLEGAR
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
# 7. CONFIGURAR USUARIO ADMIN VÍA API
# ============================================================
log_step "Configurando usuario administrador"

log_process "Esperando que File Browser esté completamente listo (10s)..."
sleep 10

# File Browser arranca con usuario por defecto: admin / admin
# Usamos la API para renombrar ese usuario y cambiar su contraseña
log_process "Autenticando con credenciales por defecto (admin/admin)..."

FB_TOKEN=$(curl -sk -X POST "https://localhost:${PORT_FILEBROWSER}/api/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin","recaptcha":""}' 2>/dev/null | \
    jq -r '.token // ""' 2>/dev/null)

if [[ -n "$FB_TOKEN" ]]; then
    # Obtener ID del usuario admin (normalmente es 1)
    ADMIN_ID=$(curl -sk -X GET "https://localhost:${PORT_FILEBROWSER}/api/users" \
        -H "X-Auth: ${FB_TOKEN}" 2>/dev/null | \
        jq -r '.[0].id // 1' 2>/dev/null)

    # Actualizar usuario: cambiar nombre y contraseña
    UPDATE_BODY=$(jq -n \
        --argjson id "$ADMIN_ID" \
        --arg u  "$FB_USER" \
        --arg p  "$FB_PASS" \
        '{
            id: $id,
            username: $u,
            password: $p,
            locale: "es",
            hideDotfiles: false,
            dateFormat: false,
            perm: {
                admin: true, execute: true, create: true,
                rename: true, modify: true, delete: true,
                share: true, download: true
            }
        }')

    HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
        -X PUT "https://localhost:${PORT_FILEBROWSER}/api/users/${ADMIN_ID}" \
        -H "X-Auth: ${FB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$UPDATE_BODY" 2>/dev/null)

    if [[ "$HTTP_STATUS" == "200" ]]; then
        log_success "Usuario '${FB_USER}' configurado correctamente ✓"
    else
        log_warning "No se pudo actualizar el usuario (HTTP ${HTTP_STATUS})."
        log_info    "Accede a ${URL_FILEBROWSER} con: admin / admin"
        log_info    "Luego cambia las credenciales en Settings → User Management"
    fi
else
    log_warning "No se pudo autenticar con File Browser."
    log_info    "Es posible que las credenciales por defecto ya hayan cambiado."
    log_info    "Accede a ${URL_FILEBROWSER} y usa: admin / admin"
fi

# ============================================================
# INSTRUCCIONES
# ============================================================
echo ""
windows_instruction "ACCESO A FILE BROWSER

1. Activa Tailscale VPN en Windows

2. Abre tu navegador y ve a:
   ${URL_FILEBROWSER}

3. Ingresa tus credenciales:
   Usuario:    ${FB_USER}
   Contraseña: (la que configuraste)

4. Tendrás acceso a:
   /apps   → Todas las aplicaciones instaladas
   /home   → Directorio home de ${ADMIN_USER} (solo lectura)
   /local  → Almacenamiento local de File Browser

FUNCIONES DISPONIBLES:
   - Navegar y ver archivos
   - Subir y descargar archivos
   - Crear, mover, renombrar y eliminar
   - Editar archivos de texto directamente
   - Compartir archivos con enlaces temporales"

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "File Browser instalado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso:${COLOR_RESET}"
echo -e "    URL:       ${COLOR_CYAN}${URL_FILEBROWSER}${COLOR_RESET}"
echo -e "    Usuario:   ${COLOR_CYAN}${FB_USER}${COLOR_RESET}"
echo -e "    Acceso:    ${COLOR_YELLOW}Solo con Tailscale VPN activo${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Carpetas accesibles:${COLOR_RESET}"
echo -e "    /apps  → ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
echo -e "    /home  → ${COLOR_CYAN}${ADMIN_HOME}${COLOR_RESET} (solo lectura)"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
echo ""
