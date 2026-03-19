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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="${REPO_DIR}/lib"

# Cargar librerías
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/utils.sh"

# ============================================================
# CARGAR CONFIGURACIÓN GUARDADA EN FASE A
# ============================================================
CONFIG_FILE="/tmp/vpsfacil_install.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    print_header "Error: Configuración no encontrada"
    log_error "No se encontró: $CONFIG_FILE"
    log_info "Ejecuta primero: sudo bash setup.sh"
    log_info "Y elige la opción: A) Instalación Automática"
    exit 1
fi

# Cargar configuración
source "$CONFIG_FILE"

# Derivar variables adicionales
_derive_config_vars

# Exportar para que los subscripts las hereden
export DOMAIN ADMIN_USER TIMEZONE
export ADMIN_HOME APPS_DIR CERTS_DIR BACKUP_DIR
export VPN_SUBDOMAIN CF_WILDCARD
export URL_PORTAINER URL_N8N URL_FILEBROWSER URL_OPENCLAW URL_KOPIA
export CERT_FILE CERT_KEY CERT_CA
export PORTAINER_ADMIN PORTAINER_PASS KOPIA_PASS

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

# Verificar que NO es root
if [[ $EUID -eq 0 ]]; then
    log_error "Este script debe ejecutarse como usuario admin, NO como root."
    log_info "Ejecuta: bash install_core.sh"
    exit 1
fi

# ============================================================
# FUNCIÓN HELPER PARA EJECUTAR SCRIPTS
# ============================================================
run_step() {
    local step_num="$1"
    local script_name="$2"
    local description="$3"

    echo ""
    log_step "Paso $step_num: $description"
    echo ""

    if bash "${REPO_DIR}/${script_name}"; then
        log_success "Paso $step_num completado ✓"
    else
        log_error "Paso $step_num falló. Aborting."
        exit 1
    fi
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
print_separator
echo ""
log_success "¡Instalación Core Completada!"
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
echo -e "    Vuelve al menú principal para instalar aplicaciones opcionales:"
echo -e "    ${COLOR_CYAN}bash setup.sh${COLOR_RESET}"
echo ""
print_separator
echo ""

# Limpiar archivo temporal
rm -f "$CONFIG_FILE"
log_success "Configuración temporal limpiada."
echo ""
