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

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config
source "${LIB_DIR}/portainer_api.sh" 2>/dev/null || true

# ============================================================
print_header "Paso 8 de 12 — Instalar Portainer"
# ============================================================

check_root

# PORTAINER_URL viene de portainer_api.sh (https://localhost:9443)
# Fallback por si portainer_api.sh no se cargó
PORTAINER_URL="${PORTAINER_URL:-https://localhost:9443}"

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
# MODO AUTOMÁTICO: Detectar si las credenciales vienen del entorno
# ============================================================
# Si PORTAINER_ADMIN y PORTAINER_PASS están definidas (desde install_core.sh),
# usar esas sin preguntar. Si no, usar valores por defecto y pedir.
PORTAINER_ADMIN="${PORTAINER_ADMIN:-}"
PORTAINER_PASS="${PORTAINER_PASS:-}"
AUTOMATIC_MODE=false

if [[ -n "$PORTAINER_ADMIN" && -n "$PORTAINER_PASS" ]]; then
    AUTOMATIC_MODE=true
    log_info "Modo automático: usando credenciales del instalador"
fi

# ============================================================
# DETECCIÓN: ¿PORTAINER YA ESTÁ INSTALADO?
# ============================================================
APP_DIR="${APPS_DIR}/portainer"
_PORTAINER_EXISTS=false

if docker ps -q --filter "name=portainer" 2>/dev/null | grep -q .; then
    _PORTAINER_EXISTS=true
    log_warning "Portainer ya está instalado y corriendo."
    echo ""
    log_info "Tienes tres opciones:"
    log_info "  1) Actualizar configuración SSL (sin pérdida de datos) ← RECOMENDADO"
    log_info "  2) Solo guardar credenciales de la cuenta existente"
    log_info "  3) Reinstalar desde cero (elimina TODOS los datos de Portainer)"
    echo ""
    REINSTALL_OPT=$(prompt_input "¿Qué deseas hacer? (1, 2 o 3)" "1")
    REINSTALL_OPT="${REINSTALL_OPT//[^123]/}"
    REINSTALL_OPT="${REINSTALL_OPT:-1}"

    if [[ "$REINSTALL_OPT" == "3" ]]; then
        log_warning "Se eliminarán todos los stacks y configuración de Portainer."
        if confirm "¿Confirmas la reinstalación completa?"; then
            log_process "Deteniendo y eliminando Portainer..."
            cd "$APP_DIR" 2>/dev/null || true
            docker compose down 2>/dev/null || docker stop portainer 2>/dev/null || true
            docker rm portainer 2>/dev/null || true
            rm -rf "${APP_DIR}/data"
            mkdir -p "${APP_DIR}/data"
            chown -R "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}/data"
            log_success "Portainer eliminado — reinstalando desde cero ✓"
            _PORTAINER_EXISTS=false
        else
            log_info "Cancelado. Cambiando a opción 1 (actualizar configuración)."
            REINSTALL_OPT="1"
        fi
    fi

    if [[ "$REINSTALL_OPT" == "1" ]]; then
        log_process "Deteniendo Portainer para actualizar configuración SSL..."
        cd "$APP_DIR" 2>/dev/null || true
        docker compose down 2>/dev/null || docker stop portainer 2>/dev/null || true
        docker rm portainer 2>/dev/null || true
        log_success "Contenedor detenido (datos conservados) ✓"
        _PORTAINER_EXISTS=false  # Forzar recreación del contenedor
    fi

    if [[ "$REINSTALL_OPT" == "2" ]]; then
        log_info "Ingresa las credenciales del administrador existente en Portainer:"
        echo ""
        PORTAINER_ADMIN=$(prompt_input "Nombre de usuario administrador" "admin")
        while true; do
            PORTAINER_ADMIN_PASS=$(prompt_password "Contraseña")
            log_process "Verificando credenciales..."
            LOGIN_TEST=$(curl -sk -X POST "${PORTAINER_URL}/api/auth" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg u "$PORTAINER_ADMIN" --arg p "$PORTAINER_ADMIN_PASS" '{username:$u,password:$p}')" 2>/dev/null)
            if echo "$LOGIN_TEST" | jq -e '.jwt' > /dev/null 2>&1; then
                log_success "Credenciales correctas ✓"
                break
            else
                log_warning "Credenciales incorrectas. Intenta de nuevo."
            fi
        done
        portainer_save_creds "$PORTAINER_ADMIN" "$PORTAINER_ADMIN_PASS"
        log_success "Credenciales guardadas → las apps usarán Portainer automáticamente ✓"
        echo ""
        print_separator
        echo ""
        log_success "Configuración completada"
        echo -e "    URL:          ${COLOR_CYAN}${URL_PORTAINER}${COLOR_RESET}"
        echo -e "    Usuario:      ${COLOR_CYAN}${PORTAINER_ADMIN}${COLOR_RESET}"
        echo ""
        exit 0
    fi
fi

# ============================================================
# 1. CREAR ESTRUCTURA DE DIRECTORIOS
# ============================================================
log_step "Creando estructura de directorios"

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
      --sslcert /certs/cert.pem
      --sslkey /certs/key.pem
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
# 4. CONFIGURAR CUENTA DE ADMINISTRADOR VÍA API
# ============================================================
log_step "Configurando cuenta de administrador de Portainer"

if [[ "$AUTOMATIC_MODE" == "false" ]]; then
    # Modo interactivo: pedir credenciales al usuario
    log_info "Crea las credenciales para acceder a Portainer:"
    echo ""

    PORTAINER_ADMIN=$(prompt_input "Nombre de usuario administrador" "admin")

    while true; do
        PORTAINER_ADMIN_PASS=$(prompt_password "Contraseña (mínimo 12 caracteres)")
        PORTAINER_ADMIN_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$PORTAINER_ADMIN_PASS" == "$PORTAINER_ADMIN_PASS2" && ${#PORTAINER_ADMIN_PASS} -ge 12 ]]; then
            break
        elif [[ "$PORTAINER_ADMIN_PASS" != "$PORTAINER_ADMIN_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden."
        else
            log_warning "Mínimo 12 caracteres."
        fi
    done
else
    # Modo automático: usar credenciales del instalador
    echo ""
    log_info "Usando credenciales del instalador automático"
    PORTAINER_ADMIN_PASS="$PORTAINER_PASS"
fi

log_process "Inicializando cuenta en Portainer (esperando que la API esté lista)..."
sleep 5

INIT_BODY=$(jq -n \
    --arg u "$PORTAINER_ADMIN" \
    --arg p "$PORTAINER_ADMIN_PASS" \
    '{username:$u,password:$p}')

INIT_RESP=$(curl -sk -X POST "${PORTAINER_URL}/api/users/admin/init" \
    -H "Content-Type: application/json" \
    -d "$INIT_BODY" 2>/dev/null)

if echo "$INIT_RESP" | jq -e '.Id' > /dev/null 2>&1; then
    log_success "Cuenta '${PORTAINER_ADMIN}' creada en Portainer ✓"
else
    INIT_MSG=$(echo "$INIT_RESP" | jq -r '.message // "sin detalles"' 2>/dev/null)
    log_warning "No se pudo crear la cuenta: ${INIT_MSG}"
    log_info    "Verifica las credenciales manualmente en ${URL_PORTAINER}"
fi

# Guardar credenciales para uso automático por todas las apps
portainer_save_creds "$PORTAINER_ADMIN" "$PORTAINER_ADMIN_PASS"
log_success "Credenciales guardadas ✓"

# Asegurar que el entorno Docker local está inicializado en Portainer
# (en versiones recientes de CE, puede no crearse automáticamente)
log_process "Verificando entorno Docker local en Portainer..."
local_jwt=$(portainer_login "$PORTAINER_ADMIN" "$PORTAINER_ADMIN_PASS" 2>/dev/null) || local_jwt=""
if [[ -n "$local_jwt" ]]; then
    portainer_ensure_endpoint "$local_jwt"
    local_eid=$(portainer_endpoint_id "$local_jwt" 2>/dev/null) || local_eid=""
    if [[ -n "$local_eid" ]]; then
        log_success "Entorno Docker local verificado (ID: ${local_eid}) ✓"
    else
        log_warning "No se pudo verificar el entorno Docker local"
    fi
else
    log_warning "No se pudo autenticar para verificar entorno Docker"
fi

# ============================================================
# RESUMEN
# ============================================================
echo ""
print_separator
echo ""
log_success "Portainer instalado exitosamente"
echo ""
log_info "Las credenciales de acceso se mostrarán al final de la instalación."
echo ""
