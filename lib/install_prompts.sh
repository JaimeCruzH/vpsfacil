#!/bin/bash
# ============================================================
# lib/install_prompts.sh — Recolectar inputs para instalación automática
# VPSfacil - Sistema Automatizado de Instalación en VPS
# ============================================================

# Función: recolectar TODOS los inputs necesarios para instalación core
# Guarda todo en archivo de configuración para que FASE B sea no-interactiva
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

    # ============================================================
    # Variables de configuración básica (ya disponibles)
    # ============================================================
    # DOMAIN, ADMIN_USER, TIMEZONE ya están definidas en setup.sh
    # (se preguntaron en ask_initial_config)

    # ============================================================
    # CREDENCIALES PORTAINER
    # ============================================================
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

    # ============================================================
    # CONTRASEÑA KOPIA (cifrado)
    # ============================================================
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

    # ============================================================
    # RESUMEN Y CONFIRMACIÓN
    # ============================================================
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

    # ============================================================
    # GUARDAR EN ARCHIVO DE CONFIGURACIÓN
    # ============================================================
    cat > "$config_file" << EOF
# ============================================================
# Configuración de Instalación Automática - VPSfacil
# Generado automáticamente por setup.sh
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

# Bandera para instalar_core.sh
INSTALLATION_MODE="automatic"
EOF

    chmod 600 "$config_file"
    log_success "Configuración guardada en: $config_file ✓"
    echo ""
}
