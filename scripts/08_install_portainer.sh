#!/bin/bash
# ============================================================
# scripts/08_install_portainer.sh — Instalar Portainer CE
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea la estructura de directorios para Portainer
#   2. Genera el docker-compose.yml con certificados SSL
#   3. Despliega Portainer Community Edition
#   4. Espera a que esté disponible en puerto 9000
#   5. Muestra la URL de acceso vía Tailscale VPN
#
# Acceso: SOLO vía Tailscale VPN
#   URL: https://portainer.vpn.DOMAIN:9000
#
# Requisitos: ejecutar como root (o admin con sudo)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config

# ============================================================
print_header "Paso 9 de 10 — Instalar Portainer"
# ============================================================

check_root

log_info "Portainer es la interfaz web para gestionar todos los"
log_info "contenedores Docker de tu servidor."
log_info ""
log_info "Accesible en: ${URL_PORTAINER}"
log_info "(requiere Tailscale VPN activo)"
echo ""

# Verificar Docker
check_docker || { log_error "Docker no está instalado. Ejecuta el paso 5 primero."; exit 1; }

# Verificar certificados SSL
if [[ ! -f "${CERT_FILE}" || ! -f "${CERT_KEY}" ]]; then
    log_error "Certificados SSL no encontrados en: ${CERTS_DIR}"
    log_info  "Ejecuta el paso 7 (Certificados SSL) primero"
    exit 1
fi

# ============================================================
# 1. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

APP_DIR="${APPS_DIR}/portainer"
mkdir -p "${APP_DIR}/data"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
chmod -R 755 "$APP_DIR"

log_success "Directorio: ${APP_DIR} ✓"

# ============================================================
# 2. CREAR DOCKER COMPOSE
# ============================================================
log_step "Generando configuración de Portainer"

cat > "${APP_DIR}/docker-compose.yml" << EOF
# ============================================================
# Portainer CE — VPSfacil
# Acceso: https://portainer.vpn.${DOMAIN}:9443
# Solo vía Tailscale VPN
# Nota: en Portainer 2.x el puerto 9443 es HTTPS, 9000 es HTTP
# ============================================================
services:
  portainer:
    image: ${IMG_PORTAINER}
    container_name: portainer
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "9443:9443"
      - "8000:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data:/data
      - ${CERT_FILE}:/certs/cert.pem:ro
      - ${CERT_KEY}:/certs/key.pem:ro
    command: >
      --tlsverify
      --tlscert /certs/cert.pem
      --tlskey /certs/key.pem
    networks:
      - vpsfacil-net

networks:
  vpsfacil-net:
    external: true
EOF

chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/docker-compose.yml"
log_success "docker-compose.yml creado ✓"

# ============================================================
# 3. DESPLEGAR PORTAINER
# ============================================================
log_step "Desplegando Portainer"

log_process "Descargando imagen de Portainer (puede tardar 1-2 minutos)..."

cd "$APP_DIR"
docker compose pull 2>&1 | tail -3
docker compose up -d

log_process "Esperando que Portainer inicie..."
wait_for_port "localhost" "9443" 60

log_success "Portainer está corriendo ✓"

# ============================================================
# 4. INSTRUCCIONES DE ACCESO
# ============================================================
echo ""
log_info "Portainer está listo. Para acceder por primera vez:"
echo ""

windows_instruction "PRIMER ACCESO A PORTAINER

1. Asegúrate de tener Tailscale VPN activo en Windows

2. Abre tu navegador y ve a:
   ${URL_PORTAINER}

3. La primera vez te pedirá crear un usuario administrador:
   - Ingresa un nombre de usuario (ej: admin)
   - Ingresa una contraseña segura (mínimo 12 caracteres)
   - Haz clic en 'Create user'

4. En la siguiente pantalla selecciona:
   'Get Started' → 'local'

5. Ya puedes ver y gestionar todos tus contenedores Docker

NOTA: El navegador puede mostrar una advertencia de certificado
la primera vez. Esto es normal — el certificado de Cloudflare
Origin requiere que el dominio resuelva a la IP de Tailscale.
Acepta la excepción de seguridad."

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Portainer instalado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso:${COLOR_RESET}"
echo -e "    URL:          ${COLOR_CYAN}${URL_PORTAINER}${COLOR_RESET}"
echo -e "    Acceso:       ${COLOR_YELLOW}Solo con Tailscale VPN activo${COLOR_RESET}"
echo -e "    Certificado:  ${COLOR_GREEN}Let's Encrypt (renovación automática)${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}"
echo -e "    ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
echo ""
log_info "Próximo paso: Instalar Kopia Backup (opción 10)"
echo ""
