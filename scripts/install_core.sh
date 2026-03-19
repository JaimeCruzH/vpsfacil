#!/bin/bash
# ============================================================
# scripts/install_core.sh — FASE B: Instalación Core Fluida
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Ejecutar como: bash install_core.sh
# Debe ejecutarse como usuario admin (NO root)
# Lee configuración de /tmp/vpsfacil_install.conf
# Ejecuta pasos 4, 6-11 sin interrupciones
# ============================================================

set -euo pipefail

# ============================================================
# DETECCIÓN: ¿REMOTE INSTALL O LOCAL?
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "$HOME")"
REPO_DIR="${SCRIPT_DIR%/*}"  # Directorio padre
LIB_DIR="${REPO_DIR}/lib"
REMOTE_INSTALL=false

# Si no podemos encontrar librerías locales, es remote install
if [[ ! -f "${LIB_DIR}/colors.sh" ]]; then
    REMOTE_INSTALL=true
    TMP_LIB="/tmp/vpsfacil_core_lib"
    mkdir -p "$TMP_LIB"

    # Descargar librerías desde GitHub
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    curl -sSL "${REPO_RAW}/lib/colors.sh"          -o "${TMP_LIB}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh"          -o "${TMP_LIB}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh"           -o "${TMP_LIB}/utils.sh"
    # NOTA: portainer_api.sh se descarga más adelante, después de que APPS_DIR esté definido

    LIB_DIR="$TMP_LIB"
fi

# Cargar librerías BÁSICAS (sin dependencias de variables)
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"

# Cargar progreso (download si es remote)
if [[ ! -f "${LIB_DIR}/progress.sh" ]]; then
    curl -sSL "${REPO_RAW}/lib/progress.sh" -o "${LIB_DIR}/progress.sh"
fi
source "${LIB_DIR}/progress.sh"

# ============================================================
# FUNCIÓN: Recolectar datos para FASE B (si no vienen de setup.sh)
# ============================================================
collect_all_inputs() {
    local config_file="/tmp/vpsfacil_install.conf"

    clear
    print_banner
    echo ""
    print_header "Instalación Automática - Recolección de Datos"
    echo ""
    log_info "Se harán todas las preguntas ahora. Después, la instalación"
    log_info "correrá sin interrupciones hasta completarse."
    echo ""
    print_separator
    echo ""

    log_step "Credenciales de Portainer"
    echo ""
    log_info "Usuario administrador de Portainer (será creado automáticamente):"
    PORTAINER_ADMIN=$(prompt_input "Usuario Portainer" "admin")
    echo ""

    while true; do
        PORTAINER_PASS=$(prompt_password "Contraseña para ${PORTAINER_ADMIN} en Portainer")
        PORTAINER_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$PORTAINER_PASS" == "$PORTAINER_PASS2" && ${#PORTAINER_PASS} -ge 8 ]]; then
            break
        elif [[ "$PORTAINER_PASS" != "$PORTAINER_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden."
        else
            log_warning "Mínimo 8 caracteres."
        fi
    done
    echo ""

    log_step "Contraseña de Cifrado de Kopia"
    echo ""
    log_warning "Esta contraseña cifra tus backups. Guárdala en un lugar seguro."
    log_info "SIN ella, no podrás restaurar tus backups."
    echo ""

    while true; do
        KOPIA_PASS=$(prompt_password "Contraseña para cifrar backups de Kopia")
        KOPIA_PASS2=$(prompt_password "Confirma la contraseña")
        if [[ "$KOPIA_PASS" == "$KOPIA_PASS2" && ${#KOPIA_PASS} -ge 8 ]]; then
            break
        elif [[ "$KOPIA_PASS" != "$KOPIA_PASS2" ]]; then
            log_warning "Las contraseñas no coinciden."
        else
            log_warning "Mínimo 8 caracteres."
        fi
    done
    echo ""

    print_separator
    echo ""
    log_info "Resumen de configuración:"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Dominio:${COLOR_RESET}           ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Usuario admin:${COLOR_RESET}      ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo -e "   ${COLOR_BOLD_WHITE}Zona horaria:${COLOR_RESET}       ${COLOR_CYAN}${TIMEZONE}${COLOR_RESET}"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Portainer:${COLOR_RESET}"
    echo -e "     Usuario:     ${COLOR_CYAN}${PORTAINER_ADMIN}${COLOR_RESET}"
    echo -e "     Contraseña:  ●●●●●●●●"
    echo ""
    echo -e "   ${COLOR_BOLD_WHITE}Kopia:${COLOR_RESET}"
    echo -e "     Cifrado:     ●●●●●●●●"
    echo ""
    print_separator
    echo ""

    if ! confirm "¿Es correcta esta configuración?"; then
        log_info "Volviendo atrás..."
        collect_all_inputs
        return
    fi

    cat > "$config_file" << EOF
# ============================================================
# Configuración de Instalación Automática - VPSfacil
# Generado automáticamente por install_core.sh
# NO editar manualmente
# ============================================================

# Configuración básica
DOMAIN="${DOMAIN}"
ADMIN_USER="${ADMIN_USER}"
TIMEZONE="${TIMEZONE}"
INSTALLATION_DATE="$(date '+%Y-%m-%d')"

# Credenciales Portainer
PORTAINER_ADMIN="${PORTAINER_ADMIN}"
PORTAINER_PASS="${PORTAINER_PASS}"

# Contraseña Kopia
KOPIA_PASS="${KOPIA_PASS}"

# Bandera para install_core.sh
INSTALLATION_MODE="automatic"
EOF

    chmod 644 "$config_file"
    log_success "Configuración guardada en: $config_file ✓"
    echo ""
}

# ============================================================
# CARGAR CONFIGURACIÓN GUARDADA EN FASE A (O RECOLECTAR SI NO EXISTE)
# ============================================================
# Buscar configuración en los mismos lugares donde setup.sh la guarda
CONFIG_FILE=""

if [[ -f "/tmp/vpsfacil_setup.conf" ]]; then
    CONFIG_FILE="/tmp/vpsfacil_setup.conf"
elif [[ -f "${HOME}/setup.conf" ]]; then
    CONFIG_FILE="${HOME}/setup.conf"
elif [[ -f "/root/setup.conf" ]]; then
    CONFIG_FILE="/root/setup.conf"
fi

if [[ -z "$CONFIG_FILE" ]]; then
    log_info "No se encontró configuración previa. Recolectando datos..."
    echo ""
    collect_all_inputs
    CONFIG_FILE="/tmp/vpsfacil_install.conf"
fi

# Cargar configuración
source "$CONFIG_FILE"

# Derivar variables adicionales
_derive_config_vars

# Cargar portainer_api (requiere APPS_DIR definido por _derive_config_vars)
if [[ ! -f "${LIB_DIR}/portainer_api.sh" ]]; then
    curl -sSL "${REPO_RAW}/lib/portainer_api.sh" -o "${LIB_DIR}/portainer_api.sh"
fi
source "${LIB_DIR}/portainer_api.sh"

# Exportar para que los subscripts las hereden
export DOMAIN ADMIN_USER TIMEZONE
export ADMIN_HOME APPS_DIR CERTS_DIR BACKUP_DIR
export VPN_SUBDOMAIN CF_WILDCARD
export URL_PORTAINER URL_N8N URL_FILEBROWSER URL_OPENCLAW URL_KOPIA
export CERT_FILE CERT_KEY CERT_CA
export PORTAINER_ADMIN PORTAINER_PASS KOPIA_PASS

# ============================================================
# INICIALIZAR PROGRESO
# ============================================================
progress_init

# ============================================================
# VERIFICACIÓN INICIAL
# ============================================================
clear
print_banner
echo ""
print_header "FASE B: Instalación Core Fluida"
echo ""
log_info "Ejecutando pasos 4-11 de instalación sin interrupciones."
log_info "Tiempo estimado: 15-20 minutos"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Configuración:${COLOR_RESET}"
echo -e "    Dominio:  ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
echo -e "    Usuario:  ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
echo ""
print_separator
echo ""

# Mostrar progreso actual (si hay instalación previa)
progress_show
wait_for_user "Presiona Enter para continuar..."

# Verificar que NO es root
if [[ $EUID -eq 0 ]]; then
    log_error "Este script debe ejecutarse como usuario admin, NO como root."
    log_info "Ejecuta: bash install_core.sh"
    exit 1
fi

# ============================================================
# FUNCIÓN HELPER PARA EJECUTAR SCRIPTS CON PROGRESO
# ============================================================
run_step() {
    local step_num="$1"
    local script_name="$2"
    local description="$3"

    # Mostrar progreso actual
    progress_show

    echo ""
    log_step "Paso $step_num: $description"
    echo ""

    # Registrar inicio del paso
    progress_start_step "$step_num"

    # Ejecutar el script
    if [[ "$REMOTE_INSTALL" == "true" ]]; then
        # Descargar script temporalmente desde GitHub
        local REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
        bash <(curl -sSL "${REPO_RAW}/${script_name}") 2>&1
    else
        # Ejecutar script local
        bash "${REPO_DIR}/${script_name}" 2>&1
    fi

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "Paso $step_num completado ✓"
        progress_complete_step "$step_num"
    else
        log_error "Paso $step_num falló con código $exit_code"
        progress_fail_step "$step_num" "Exit code $exit_code"
        echo ""
        log_error "INSTALACIÓN DETENIDA"
        log_info "El progreso ha sido guardado. Cuando resuelvas el error,"
        log_info "reconéctate y ejecuta nuevamente: bash ~/install_core.sh"
        exit 1
    fi

    # Mostrar progreso actualizado
    echo ""
}

# ============================================================
# EJECUTAR PASOS 4-11
# ============================================================
# Nota: Los pasos 1-3 y 5 ya se ejecutaron en FASE A (setup.sh)

run_step 4 "scripts/03_install_firewall.sh" "Instalar Firewall UFW"
run_step 6 "scripts/04_install_docker.sh" "Instalar Docker & Docker Compose"
run_step 7 "scripts/06_setup_certificates.sh" "Configurar Certificados SSL"
run_step 8 "scripts/07_setup_dns.sh" "Configurar DNS en Cloudflare"
run_step 9 "scripts/08_install_portainer.sh" "Instalar Portainer"
run_step 10 "scripts/09_install_kopia.sh" "Instalar Kopia Backup"
run_step 11 "scripts/10_install_filebrowser.sh" "Instalar File Browser"

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
echo ""

# Mostrar progreso final
progress_show

# Calcular duración total
total_seconds=$(progress_get_total_duration)
total_mins=$((total_seconds / 60))
total_secs=$((total_seconds % 60))

echo ""
print_separator
echo ""
log_success "¡Instalación Core Completada!"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Tiempo total:${COLOR_RESET}      ${COLOR_CYAN}${total_mins}m ${total_secs}s${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Acceso a las aplicaciones:${COLOR_RESET}"
echo -e "    Portainer:    ${COLOR_CYAN}${URL_PORTAINER}${COLOR_RESET}"
echo -e "    File Browser: ${COLOR_CYAN}${URL_FILEBROWSER}${COLOR_RESET}"
echo -e "    Kopia Backup: ${COLOR_CYAN}${URL_KOPIA}${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Credenciales:${COLOR_RESET}"
echo -e "    Portainer Usuario:  ${COLOR_CYAN}${PORTAINER_ADMIN}${COLOR_RESET}"
echo -e "    File Browser:       ${COLOR_CYAN}admin / admin${COLOR_RESET} (sin auth, solo VPN)"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Próximo paso:${COLOR_RESET}"
echo -e "    Para instalar aplicaciones opcionales (N8N, OpenClaw):"
echo -e "    ${COLOR_CYAN}bash ~/install_core.sh${COLOR_RESET}"
echo ""
print_separator
echo ""

# Limpiar archivo temporal
rm -f "$CONFIG_FILE"
log_success "Configuración temporal limpiada."
echo ""
