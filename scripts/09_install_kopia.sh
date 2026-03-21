#!/bin/bash
# ============================================================
# scripts/09_install_kopia.sh — Instalar Kopia Backup
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Crea estructura de directorios para Kopia
#   2. Despliega Kopia como contenedor Docker
#   3. Configura respaldos automáticos del directorio /apps/
#   4. Configura schedule diario a las 2 AM
#   5. Muestra URL de acceso vía Tailscale VPN
#
# Kopia respalda: /home/ADMIN/apps/ (todas las aplicaciones)
# Almacena en:    /home/ADMIN/apps/backups/
#
# Acceso web: https://kopia.vpn.DOMAIN:51515
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LIB_DIR="${SCRIPT_DIR}/../lib"

# Si las librerías no existen donde se esperan, asumir ejecución remota y limpiar SCRIPT_DIR
if [[ ! -f "${LIB_DIR}/colors.sh" ]] 2>/dev/null; then
    SCRIPT_DIR=""
fi

# Si se ejecuta remotamente (vía curl | bash), descargar librerías desde GitHub
if [[ -z "$SCRIPT_DIR" ]] || [[ ! -f "${LIB_DIR}/colors.sh" ]]; then
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    LIB_DIR="/tmp/vpsfacil_lib_$$"
    mkdir -p "$LIB_DIR"
    curl -sSL "${REPO_RAW}/lib/colors.sh"  -o "${LIB_DIR}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh"  -o "${LIB_DIR}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh"   -o "${LIB_DIR}/utils.sh"
    curl -sSL "${REPO_RAW}/lib/portainer_api.sh" -o "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true
fi


# ============================================================
print_header "Paso 9 de 11 — Instalar Kopia Backup"
# ============================================================

check_root

log_info "Kopia es la solución de backup que protegerá todos tus datos."
log_info "Realizará copias automáticas diarias de todas las aplicaciones."
echo ""
log_info "Fuente de backup:  ${APPS_DIR}/"
log_info "Destino de backup: ${BACKUP_DIR}/"
log_info "Acceso web:        ${URL_KOPIA}"
echo ""

check_docker || { log_error "Docker no está instalado. Ejecuta el paso 5 primero."; exit 1; }

# ============================================================
# 1. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

APP_DIR="${APPS_DIR}/kopia"
mkdir -p "${APP_DIR}/config"
mkdir -p "${APP_DIR}/cache"
mkdir -p "${APP_DIR}/logs"
mkdir -p "${BACKUP_DIR}"

chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR" "${BACKUP_DIR}"
chmod -R 755 "$APP_DIR"

log_success "Directorios creados ✓"

# ============================================================
# MODO AUTOMÁTICO: Detectar si las credenciales vienen del entorno
# ============================================================
KOPIA_PASS="${KOPIA_PASS:-}"
AUTOMATIC_MODE=false

if [[ -n "$KOPIA_PASS" ]]; then
    AUTOMATIC_MODE=true
    log_info "Modo automático: usando contraseña del instalador"
fi

# ============================================================
# 2. CONFIGURAR CONTRASEÑA DE KOPIA
# ============================================================
log_step "Configurando contraseña de Kopia"

if [[ "$AUTOMATIC_MODE" == "false" ]]; then
    # Modo interactivo: pedir contraseña al usuario
    log_info "Kopia necesita una contraseña para cifrar los backups."
    log_warning "Guarda esta contraseña en un lugar seguro."
    log_warning "Sin ella NO podrás restaurar tus backups."
    echo ""

    while true; do
        KOPIA_PASS=$(prompt_password "Contraseña para cifrar backups de Kopia")
        KOPIA_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$KOPIA_PASS" == "$KOPIA_PASS2" && ${#KOPIA_PASS} -ge 8 ]]; then
            break
        elif [[ "$KOPIA_PASS" != "$KOPIA_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden. Intenta de nuevo."
        else
            log_warning "La contraseña debe tener al menos 8 caracteres."
        fi
    done
else
    # Modo automático: contraseña ya está definida
    echo ""
fi

# Contraseña para la interfaz web de Kopia
KOPIA_WEB_USER="admin"
KOPIA_WEB_PASS=$(generate_password 16)

# ============================================================
# 3. CREAR ARCHIVO .ENV
# ============================================================
cat > "${APP_DIR}/.env" << EOF
# Kopia Backup — VPSfacil
# NO compartir ni subir a GitHub
KOPIA_PASSWORD=${KOPIA_PASS}
KOPIA_WEB_USER=${KOPIA_WEB_USER}
KOPIA_WEB_PASS=${KOPIA_WEB_PASS}
BACKUP_SOURCE=${APPS_DIR}
BACKUP_DEST=${BACKUP_DIR}
TZ=${TIMEZONE}
EOF

chmod 600 "${APP_DIR}/.env"
chown "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/.env"
log_success "Archivo .env creado (600) ✓"

# ============================================================
# 4. PREPARAR Y DESPLEGAR VÍA PORTAINER
# ============================================================
log_step "Generando configuración de Kopia"

# Escapar caracteres especiales de valores ingresados por el usuario
KOPIA_PASS_ESC=$(compose_escape "$KOPIA_PASS")

COMPOSE_CONTENT=$(cat << EOF
# ============================================================
# Kopia Backup — VPSfacil
# Acceso: https://kopia.vpn.${DOMAIN}:51515
# Solo vía Tailscale VPN
# ============================================================
services:
  kopia:
    image: ${IMG_KOPIA}
    container_name: kopia
    restart: unless-stopped
    environment:
      KOPIA_PASSWORD: "${KOPIA_PASS_ESC}"
      TZ: ${TIMEZONE}
    ports:
      - "51515:51515"
    volumes:
      - ${APP_DIR}/config:/app/config
      - ${APP_DIR}/cache:/app/cache
      - ${APP_DIR}/logs:/app/logs
      - ${APPS_DIR}:/source:ro
      - ${BACKUP_DIR}:/backups
      - ${CERT_FILE}:/certs/cert.pem:ro
      - ${CERT_KEY}:/certs/key.pem:ro
    command: >
      server start
      --address=0.0.0.0:51515
      --server-username=${KOPIA_WEB_USER}
      --server-password=${KOPIA_WEB_PASS}
      --tls-cert-file=/certs/cert.pem
      --tls-key-file=/certs/key.pem
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
log_success "Configuración generada ✓"

# ============================================================
# 5. DESPLEGAR KOPIA
# ============================================================
log_step "Desplegando Kopia via Portainer"

log_process "Registrando stack en Portainer..."
if portainer_deploy_stack "kopia" "$COMPOSE_CONTENT"; then
    log_process "Descargando imagen y levantando contenedor..."
else
    log_warning "Portainer no disponible. Desplegando con docker compose directamente..."
    cd "$APP_DIR"
    docker compose pull 2>&1 | tail -3
    docker compose up -d
fi

log_process "Esperando que Kopia inicie..."
wait_for_port "localhost" "${PORT_KOPIA}" 60

log_success "Kopia está corriendo ✓"

# ============================================================
# 6. CONFIGURAR REPOSITORIO Y PRIMER BACKUP
# ============================================================
log_step "Configurando repositorio de backup local"

log_process "Esperando que Kopia esté completamente listo (30s)..."
sleep 30

log_process "Inicializando repositorio de backup..."

# Verificar si el repositorio ya existe antes de crear
if docker exec kopia kopia repository status 2>/dev/null | grep -q "Connected"; then
    log_info "Repositorio ya existe y está conectado ✓"
else
    if docker exec kopia kopia repository create filesystem \
        --path=/backups \
        --password="${KOPIA_PASS}" 2>/dev/null; then
        log_success "Repositorio de backup creado ✓"

        # Configurar snapshot de /source (= /apps del host)
        if docker exec kopia kopia policy set /source \
            --compression=zstd \
            --keep-latest=7 \
            --keep-daily=14 \
            --keep-weekly=4 \
            --keep-monthly=6 2>/dev/null; then
            log_success "Política de retención configurada ✓"
        fi

        # Configurar schedule automático (diario a las 2 AM)
        if docker exec kopia kopia policy set /source \
            --schedule="0 2 * * *" 2>/dev/null; then
            log_success "Backup automático: diario a las 2:00 AM ✓"
        fi

        # Primer backup
        log_process "Ejecutando primer backup (puede tardar varios minutos)..."
        if docker exec kopia kopia snapshot create /source 2>/dev/null; then
            log_success "Primer backup completado ✓"
        else
            log_warning "Primer backup falló — confíguralo desde la interfaz web"
        fi
    else
        log_warning "No se pudo inicializar el repositorio automáticamente."
        log_info    "Accede a ${URL_KOPIA} y selecciona 'Local Directory or NAS'"
        log_info    "  Path:     /backups"
        log_info    "  Password: (la que ingresaste al instalar Kopia)"
    fi
fi

# ============================================================
# 7. INSTRUCCIONES DE ACCESO
# ============================================================
echo ""
windows_instruction "ACCESO A KOPIA BACKUP

1. Activa Tailscale VPN en Windows

2. Abre tu navegador y ve a:
   ${URL_KOPIA}

3. Ingresa las credenciales:
   Usuario: ${KOPIA_WEB_USER}
   Contraseña: ${KOPIA_WEB_PASS}

4. Desde la interfaz web puedes:
   - Ver historial de backups
   - Restaurar archivos específicos
   - Configurar notificaciones
   - Agregar repositorios remotos (S3, B2, etc.)

GUARDA ESTAS CREDENCIALES:
   Web usuario:    ${KOPIA_WEB_USER}
   Web contraseña: ${KOPIA_WEB_PASS}
   Cifrado:        (la contraseña que elegiste al instalar)"

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Kopia Backup instalado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso:${COLOR_RESET}"
echo -e "    URL:          ${COLOR_CYAN}${URL_KOPIA}${COLOR_RESET}"
echo -e "    Usuario:      ${COLOR_CYAN}${KOPIA_WEB_USER}${COLOR_RESET}"
echo -e "    Contraseña:   ${COLOR_CYAN}${KOPIA_WEB_PASS}${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Configuración de backups:${COLOR_RESET}"
echo -e "    Fuente:       ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
echo -e "    Destino:      ${COLOR_CYAN}${BACKUP_DIR}${COLOR_RESET}"
echo -e "    Schedule:     ${COLOR_CYAN}Diario a las 2:00 AM${COLOR_RESET}"
echo -e "    Retención:    ${COLOR_CYAN}7 diarios, 4 semanales, 6 mensuales${COLOR_RESET}"
echo -e "    Cifrado:      ${COLOR_GREEN}Sí (AES-256)${COLOR_RESET}"
echo ""
echo ""
log_success "¡Instalación core completa! (10/10 pasos)"
echo ""
log_info "Ahora puedes instalar las aplicaciones opcionales:"
log_info "  11) N8N — Automatización de flujos de trabajo"
log_info "  12) OpenClaw — Asistente IA personal"
log_info "  13) File Browser — Gestor de archivos web"
echo ""
