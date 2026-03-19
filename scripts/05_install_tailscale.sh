#!/bin/bash
# ============================================================
# scripts/05_install_tailscale.sh — Instalar Tailscale VPN
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Instala Tailscale como servicio del sistema (no Docker)
#   2. Inicia la autenticación con tu cuenta de Tailscale
#   3. Obtiene la IP VPN asignada (100.x.x.x)
#   4. Guarda la IP en la configuración para usarla en DNS
#   5. Habilita el inicio automático con el sistema
#
# Por qué Tailscale como servicio y no Docker:
#   Tailscale necesita acceso profundo al kernel de Linux
#   (módulo WireGuard) para funcionar. Como servicio del sistema
#   tiene el acceso necesario sin complicaciones extras.
#
# Requisitos: ejecutar como root
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LIB_DIR="${SCRIPT_DIR}/../lib"

# Si se ejecuta remotamente (vía curl | bash), descargar librerías desde GitHub
if [[ ! -d "$LIB_DIR" ]] || [[ ! -f "${LIB_DIR}/colors.sh" ]]; then
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    LIB_DIR="/tmp/vpsfacil_lib_$$"
    mkdir -p "$LIB_DIR"
    curl -sSL "${REPO_RAW}/lib/colors.sh"  -o "${LIB_DIR}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh"  -o "${LIB_DIR}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh"   -o "${LIB_DIR}/utils.sh"
fi

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"
source_config

# ============================================================
print_header "Paso 6 de 10 — Instalar Tailscale VPN"
# ============================================================

check_root

# Definir funciones antes de cualquier uso
_save_tailscale_ip() {
    local ts_ip="$1"
    local config_file="${ADMIN_HOME}/setup.conf"

    if [[ -f "$config_file" ]]; then
        if grep -q "^TAILSCALE_IP=" "$config_file"; then
            sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=\"${ts_ip}\"|" "$config_file"
        else
            echo "TAILSCALE_IP=\"${ts_ip}\"" >> "$config_file"
        fi
        chown "${ADMIN_USER}:${ADMIN_USER}" "$config_file"
    fi
}

_apply_tailscale_ufw() {
    if command -v ufw &>/dev/null; then
        ufw allow in on tailscale0 comment "Permitir todo tráfico VPN Tailscale" 2>/dev/null || true
        log_success "UFW: tráfico entrante por Tailscale VPN permitido ✓"
    fi
}

log_info "Tailscale crea una red privada segura entre tu PC y el servidor."
log_info "Es la clave de la arquitectura: todas las apps solo son"
log_info "accesibles cuando Tailscale está activo en tu dispositivo."
echo ""
log_info "Necesitarás una cuenta de Tailscale (gratuita para uso personal)."
log_info "Si no tienes cuenta, créala en: https://tailscale.com"
echo ""

# ============================================================
# 1. VERIFICAR SI TAILSCALE YA ESTÁ INSTALADO
# ============================================================
log_step "Verificando instalación existente de Tailscale"

if command_exists tailscale; then
    TS_VERSION=$(tailscale version 2>/dev/null | head -1 || echo "desconocida")
    log_info "Tailscale ya está instalado: ${TS_VERSION}"

    TS_STATUS=$(tailscale status --json 2>/dev/null | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState','unknown'))" \
        2>/dev/null || echo "unknown")

    if [[ "$TS_STATUS" == "Running" ]]; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "$TAILSCALE_IP" ]]; then
            log_success "Tailscale ya está conectado. IP VPN: ${TAILSCALE_IP} ✓"
            _save_tailscale_ip "$TAILSCALE_IP"
            _apply_tailscale_ufw
            log_info "Próximo paso: Configurar Certificados SSL (opción 7)"
            exit 0
        fi
    fi

    log_info "Tailscale está instalado pero no conectado. Continuando..."
else
    # ============================================================
    # 2. INSTALAR TAILSCALE
    # ============================================================
    log_step "Instalando Tailscale"

    log_process "Descargando instalador oficial de Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh 2>&1 | tail -5

    log_success "Tailscale instalado ✓"
fi

# ============================================================
# 3. INICIAR SERVICIO
# ============================================================
log_step "Iniciando servicio Tailscale"

systemctl enable tailscaled > /dev/null 2>&1
systemctl start tailscaled > /dev/null 2>&1

sleep 3

if systemctl is-active tailscaled > /dev/null 2>&1; then
    log_success "Servicio Tailscale activo ✓"
else
    log_error "El servicio Tailscale no pudo iniciarse"
    log_info  "Verifica con: systemctl status tailscaled"
    exit 1
fi

# ============================================================
# 4. AUTENTICAR CON CUENTA TAILSCALE
# ============================================================
log_step "Autenticando con tu cuenta de Tailscale"

echo ""
log_info "A continuación aparecerá una URL de autenticación."
log_info "Debes abrirla en tu navegador para conectar este servidor"
log_info "a tu cuenta de Tailscale."
echo ""

windows_instruction "CÓMO AUTENTICAR TAILSCALE

1. Copia la URL que aparecerá a continuación en la terminal

2. Ábrela en tu navegador (Chrome, Edge, Firefox)

3. Inicia sesión en tu cuenta de Tailscale
   (o crea una cuenta gratuita en tailscale.com)

4. Haz clic en 'Connect' o 'Authorize'

5. Vuelve aquí — la terminal detectará la conexión automáticamente

NOTA: La URL tiene validez por 10 minutos.
Si expira, puedes volver a ejecutar este paso."

echo ""
wait_for_user "Presiona Enter cuando estés listo para ver la URL de autenticación..."
echo ""

# Iniciar autenticación — esto imprime la URL y espera
log_process "Iniciando autenticación (espera la URL)..."
echo ""

# tailscale up con timeout — la URL aparece casi de inmediato
# Ejecutamos en background y capturamos la URL
tailscale up \
    --accept-dns=false \
    --hostname="vps-${ADMIN_USER}" \
    2>&1 &

TS_PID=$!

# Esperar hasta 10 minutos para que el usuario autentique
log_info "Esperando que completes la autenticación en el navegador..."
log_info "(máximo 10 minutos)"
echo ""

TIMEOUT=600
ELAPSED=0
TAILSCALE_IP=""

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))

    TS_STATE=$(tailscale status --json 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState',''))" \
        2>/dev/null || echo "")

    if [[ "$TS_STATE" == "Running" ]]; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "$TAILSCALE_IP" ]]; then
            echo ""
            log_success "¡Tailscale conectado exitosamente! ✓"
            break
        fi
    fi

    # Mostrar progreso cada 15 segundos
    if [[ $((ELAPSED % 15)) -eq 0 ]]; then
        printf "."
    fi
done

# Detener el proceso de tailscale up si sigue corriendo
kill "$TS_PID" 2>/dev/null || true

if [[ -z "$TAILSCALE_IP" ]]; then
    log_error "No se pudo conectar Tailscale en el tiempo límite"
    log_info  "Intenta ejecutar este paso nuevamente"
    log_info  "O conecta manualmente con: tailscale up"
    exit 1
fi

# ============================================================
# 5. GUARDAR IP Y CONFIGURAR UFW
# ============================================================
log_step "Guardando IP de Tailscale en configuración"

_save_tailscale_ip "$TAILSCALE_IP"
log_success "IP Tailscale guardada: ${TAILSCALE_IP} ✓"

log_step "Configurando UFW para tráfico Tailscale"
_apply_tailscale_ufw

# ============================================================
# 6. VERIFICAR CONECTIVIDAD DESDE PC WINDOWS
# ============================================================
echo ""
log_info "Ahora verifica que puedes alcanzar el servidor por VPN."
echo ""

windows_instruction "VERIFICAR CONECTIVIDAD TAILSCALE DESDE WINDOWS

1. Descarga Tailscale para Windows en: https://tailscale.com/download
   (si aún no lo tienes instalado)

2. Inicia sesión con la misma cuenta que usaste para autorizar el servidor

3. Activa la VPN (toggle en ON)

4. Abre una terminal de Windows (PowerShell o CMD) y ejecuta:
   ping ${TAILSCALE_IP}

   Si recibes respuesta (Reply from ${TAILSCALE_IP}) → todo funciona ✓

5. También puedes verificar en el panel de Tailscale:
   https://login.tailscale.com/admin/machines
   Deberías ver 'vps-${ADMIN_USER}' en la lista con estado 'Connected'"

echo ""
wait_for_user "Presiona Enter cuando hayas verificado la conectividad VPN..."

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Tailscale VPN configurado exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Datos de la VPN:${COLOR_RESET}"
echo -e "    Nombre del nodo:  ${COLOR_CYAN}vps-${ADMIN_USER}${COLOR_RESET}"
echo -e "    IP Tailscale:     ${COLOR_BOLD_GREEN}${TAILSCALE_IP}${COLOR_RESET}"
echo -e "    Estado:           ${COLOR_GREEN}Conectado${COLOR_RESET}"
echo -e "    Inicio automático: ${COLOR_GREEN}Habilitado${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Esta IP se usará para:${COLOR_RESET}"
echo -e "    DNS Cloudflare:   ${COLOR_CYAN}*.vpn.${DOMAIN}${COLOR_RESET} → ${COLOR_CYAN}${TAILSCALE_IP}${COLOR_RESET}"
echo -e "    Acceso a apps:    ${COLOR_CYAN}solo desde Tailscale VPN${COLOR_RESET}"
echo ""
log_info "Próximo paso: Configurar Certificados SSL (opción 7)"
echo ""
