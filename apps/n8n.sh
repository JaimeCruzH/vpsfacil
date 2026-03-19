#!/bin/bash
# ============================================================
# apps/n8n.sh — Instalar N8N (Automatización de flujos)
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea estructura de directorios para N8N
#   2. Configura N8N con PostgreSQL 16 como base de datos
#   3. Genera contraseñas seguras automáticamente
#   4. Despliega N8N + PostgreSQL vía Docker Compose
#   5. Configura HTTPS con certificado Let's Encrypt
#
# Acceso: https://n8n.vpn.DOMAIN:5678 (solo Tailscale VPN)
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config

# ============================================================
print_header "App Opcional — Instalar N8N"
# ============================================================

check_root

log_info "N8N es una plataforma de automatización de flujos de trabajo."
log_info "Permite conectar aplicaciones, APIs y servicios sin programar."
echo ""
log_info "Se instalarán dos contenedores:"
log_info "  - N8N (la aplicación)"
log_info "  - PostgreSQL 16 (base de datos)"
echo ""
log_info "Acceso: ${URL_N8N}"
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

APP_DIR="${APPS_DIR}/n8n"
mkdir -p "${APP_DIR}/data"
mkdir -p "${APP_DIR}/postgres"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"
log_success "Directorio: ${APP_DIR} ✓"

# ============================================================
# 2. GENERAR CREDENCIALES
# ============================================================
log_step "Generando credenciales seguras"

DB_PASS=$(generate_password 24)
N8N_ENCRYPTION_KEY=$(generate_token 32)

log_success "Contraseñas generadas automáticamente ✓"

# ============================================================
# 3. PEDIR DATOS AL USUARIO
# ============================================================
log_step "Configuración de N8N"

echo ""
log_info "N8N necesita algunos datos para su configuración:"
echo ""

N8N_EMAIL=$(prompt_input "Email del usuario administrador de N8N" "admin@${DOMAIN}")

while true; do
    N8N_PASS=$(prompt_password "Contraseña para el usuario admin de N8N")
    N8N_PASS2=$(prompt_password "Confirma la contraseña")
    if [[ "$N8N_PASS" == "$N8N_PASS2" && ${#N8N_PASS} -ge 8 ]]; then
        break
    elif [[ "$N8N_PASS" != "$N8N_PASS2" ]]; then
        log_warning "Las contraseñas no coinciden."
    else
        log_warning "Mínimo 8 caracteres."
    fi
done

N8N_FIRSTNAME=$(prompt_input "Nombre del administrador" "Admin")
N8N_LASTNAME=$(prompt_input "Apellido del administrador" "User")

# ============================================================
# 4. CREAR ARCHIVO .ENV
# ============================================================
log_step "Guardando configuración"

cat > "${APP_DIR}/.env" << EOF
# N8N + PostgreSQL — VPSfacil
# NO compartir ni subir a GitHub

# Base de datos PostgreSQL
DB_USER=n8n_user
DB_PASSWORD=${DB_PASS}
DB_NAME=n8n_db
DB_HOST=postgres_n8n

# N8N
N8N_HOST=n8n.vpn.${DOMAIN}
N8N_PORT=${PORT_N8N}
N8N_PROTOCOL=https
WEBHOOK_URL=https://n8n.vpn.${DOMAIN}:${PORT_N8N}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Usuario inicial N8N
N8N_EMAIL=${N8N_EMAIL}
N8N_PASSWORD=${N8N_PASS}
N8N_FIRSTNAME=${N8N_FIRSTNAME}
N8N_LASTNAME=${N8N_LASTNAME}

# Sistema
TZ=${TIMEZONE}
GENERIC_TIMEZONE=${TIMEZONE}
EOF

chmod 600 "${APP_DIR}/.env"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"
log_success "Archivo .env creado ✓"

# ============================================================
# 5. CREAR DOCKER COMPOSE
# ============================================================
log_step "Generando docker-compose.yml"

cat > "${APP_DIR}/docker-compose.yml" << EOF
# ============================================================
# N8N + PostgreSQL — VPSfacil
# Acceso: https://n8n.vpn.${DOMAIN}:${PORT_N8N}
# Solo vía Tailscale VPN
# ============================================================
services:
  postgres_n8n:
    image: ${IMG_POSTGRES}
    container_name: postgres_n8n
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${DB_USER}
      POSTGRES_PASSWORD: \${DB_PASSWORD}
      POSTGRES_DB: \${DB_NAME}
    volumes:
      - ./postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${DB_USER} -d \${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-internal

  n8n:
    image: ${IMG_N8N}
    container_name: n8n
    restart: unless-stopped
    depends_on:
      postgres_n8n:
        condition: service_healthy
    env_file: .env
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: \${DB_HOST}
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: \${DB_NAME}
      DB_POSTGRESDB_USER: \${DB_USER}
      DB_POSTGRESDB_PASSWORD: \${DB_PASSWORD}
      N8N_HOST: \${N8N_HOST}
      N8N_PORT: \${N8N_PORT}
      N8N_PROTOCOL: \${N8N_PROTOCOL}
      WEBHOOK_URL: \${WEBHOOK_URL}
      N8N_ENCRYPTION_KEY: \${N8N_ENCRYPTION_KEY}
      GENERIC_TIMEZONE: \${GENERIC_TIMEZONE}
      TZ: \${TZ}
      N8N_BASIC_AUTH_ACTIVE: "false"
      N8N_USER_MANAGEMENT_DISABLED: "false"
      N8N_DEFAULT_BINARY_DATA_MODE: filesystem
      N8N_RUNNERS_ENABLED: "true"
      N8N_EDITOR_BASE_URL: \${WEBHOOK_URL}
      N8N_SSL_CERT: /certs/cert.pem
      N8N_SSL_KEY: /certs/key.pem
    ports:
      - "${PORT_N8N}:${PORT_N8N}"
    volumes:
      - ./data:/home/node/.n8n
      - ${CERT_FILE}:/certs/cert.pem:ro
      - ${CERT_KEY}:/certs/key.pem:ro
    networks:
      - n8n-internal
      - vpsfacil-net

networks:
  n8n-internal:
    driver: bridge
  vpsfacil-net:
    external: true
EOF

chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/docker-compose.yml"
log_success "docker-compose.yml creado ✓"

# ============================================================
# 6. DESPLEGAR
# ============================================================
log_step "Desplegando N8N y PostgreSQL"

cd "$APP_DIR"
log_process "Descargando imágenes (puede tardar 2-4 minutos)..."
docker compose pull 2>&1 | tail -5
docker compose up -d

log_process "Esperando que PostgreSQL y N8N inicien..."
wait_for_port "localhost" "${PORT_N8N}" "${TIMEOUT_APP_START}"

log_success "N8N está corriendo ✓"

# ============================================================
# INSTRUCCIONES DE ACCESO
# ============================================================
echo ""
windows_instruction "ACCESO A N8N

1. Activa Tailscale VPN en Windows

2. Abre tu navegador y ve a:
   ${URL_N8N}

3. Ingresa tus credenciales:
   Email:      ${N8N_EMAIL}
   Contraseña: (la que configuraste)

4. ¡Listo! Puedes crear tus primeros flujos de trabajo."

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "N8N instalado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso:${COLOR_RESET}"
echo -e "    URL:       ${COLOR_CYAN}${URL_N8N}${COLOR_RESET}"
echo -e "    Email:     ${COLOR_CYAN}${N8N_EMAIL}${COLOR_RESET}"
echo -e "    Acceso:    ${COLOR_YELLOW}Solo con Tailscale VPN activo${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Directorio:${COLOR_RESET}  ${COLOR_CYAN}${APP_DIR}${COLOR_RESET}"
echo ""
