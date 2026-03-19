#!/bin/bash
# ============================================================
# setup.sh — Script principal de VPSfacil
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Uso:
#   bash <(curl -sSL setup.TUDOMINIO.com)
#   o directamente: sudo bash setup.sh
#
# Requisitos:
#   - Debian 12 (Bookworm)
#   - Ejecutar como root
# ============================================================

set -euo pipefail

# ============================================================
# CARGAR LIBRERÍAS BASE
# ============================================================
# Detectar directorio del script para cargar las librerías
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cuando se ejecuta via curl (bash <(curl ...)), BASH_SOURCE[0]
# es /dev/stdin. En ese caso, descargamos libs desde GitHub.
if [[ "$SCRIPT_DIR" == "" || "$SCRIPT_DIR" == "/dev/fd" || "$SCRIPT_DIR" == "/proc/"* ]]; then
    # Ejecución via curl — descargar librerías temporalmente
    REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
    TMP_LIB="/tmp/vpsfacil_lib"
    mkdir -p "$TMP_LIB"
    curl -sSL "${REPO_RAW}/lib/colors.sh"            -o "${TMP_LIB}/colors.sh"
    curl -sSL "${REPO_RAW}/lib/config.sh"            -o "${TMP_LIB}/config.sh"
    curl -sSL "${REPO_RAW}/lib/utils.sh"             -o "${TMP_LIB}/utils.sh"
    curl -sSL "${REPO_RAW}/lib/menu.sh"              -o "${TMP_LIB}/menu.sh"
    curl -sSL "${REPO_RAW}/lib/install_prompts.sh"   -o "${TMP_LIB}/install_prompts.sh"
    LIB_DIR="$TMP_LIB"
    REMOTE_INSTALL=true
else
    LIB_DIR="${SCRIPT_DIR}/lib"
    REMOTE_INSTALL=false
fi

# shellcheck source=lib/colors.sh
source "${LIB_DIR}/colors.sh"
# shellcheck source=lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=lib/utils.sh
source "${LIB_DIR}/utils.sh"
# shellcheck source=lib/install_prompts.sh
source "${LIB_DIR}/install_prompts.sh"

# ============================================================
# VERIFICACIÓN INICIAL
# ============================================================
check_root

# ============================================================
# PANTALLA DE BIENVENIDA
# ============================================================
clear
print_banner

echo -e "${COLOR_BOLD_WHITE}  Bienvenido a VPSfacil${COLOR_RESET}"
echo ""
echo -e "  Este asistente instalará y configurará tu VPS paso a paso."
echo -e "  Al finalizar tendrás un servidor seguro con acceso VPN y"
echo -e "  las aplicaciones que elijas, listas para usar."
echo ""
echo -e "  ${COLOR_BOLD_YELLOW}Tiempo estimado de instalación base: 15-25 minutos${COLOR_RESET}"
echo ""
print_separator
echo ""

# ============================================================
# CONFIGURACIÓN INICIAL (dominio y usuario)
# ============================================================
# Si ya existe setup.conf, lo cargamos. Si no, preguntamos.
CONFIG_FILE="/tmp/vpsfacil_setup.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    log_info "Configuración previa encontrada. Cargando..."
    source "$CONFIG_FILE"
    _derive_config_vars
    echo ""
    echo -e "   Dominio:      ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "   Usuario:      ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo -e "   Zona horaria: ${COLOR_CYAN}${TIMEZONE}${COLOR_RESET}"
    echo ""
    if ! confirm "¿Usar esta configuración guardada?"; then
        ask_initial_config
    fi
else
    ask_initial_config
fi

# Exportar variables para que los subscripts las hereden
export DOMAIN ADMIN_USER TIMEZONE
export ADMIN_HOME APPS_DIR CERTS_DIR BACKUP_DIR
export VPN_SUBDOMAIN CF_WILDCARD
export URL_PORTAINER URL_N8N URL_FILEBROWSER URL_OPENCLAW URL_KOPIA
export CERT_FILE CERT_KEY CERT_CA

# ============================================================
# MENÚ PRINCIPAL
# ============================================================
show_main_menu() {
    clear
    print_banner

    echo -e "  ${COLOR_BOLD_WHITE}Configuración activa:${COLOR_RESET}"
    echo -e "  Dominio: ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}  |  Usuario: ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo ""
    print_separator
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}INSTALACIÓN CORE (requerida, en este orden):${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_GREEN}1)${COLOR_RESET} Pre-verificaciones del sistema"
    echo -e "  ${COLOR_BOLD_GREEN}2)${COLOR_RESET} Crear usuario admin (${ADMIN_USER})"
    echo -e "  ${COLOR_BOLD_GREEN}3)${COLOR_RESET} Seguridad SSH (deshabilitar acceso root)"
    echo -e "  ${COLOR_BOLD_GREEN}4)${COLOR_RESET} Instalar Firewall UFW"
    echo -e "  ${COLOR_BOLD_GREEN}5)${COLOR_RESET} Instalar Docker & Docker Compose"
    echo -e "  ${COLOR_BOLD_GREEN}6)${COLOR_RESET} Instalar Tailscale VPN"
    echo -e "  ${COLOR_BOLD_GREEN}7)${COLOR_RESET} Configurar Certificados SSL (Let's Encrypt)"
    echo -e "  ${COLOR_BOLD_GREEN}8)${COLOR_RESET} Configurar DNS en Cloudflare"
    echo -e "  ${COLOR_BOLD_GREEN}9)${COLOR_RESET} Instalar Portainer (gestión de contenedores)"
    echo -e "  ${COLOR_BOLD_GREEN}10)${COLOR_RESET} Instalar Kopia Backup"
    echo -e "  ${COLOR_BOLD_GREEN}11)${COLOR_RESET} Instalar File Browser (gestor de archivos web)"
    echo ""
    print_separator
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}APLICACIONES OPCIONALES:${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_CYAN}12)${COLOR_RESET} Instalar N8N (automatización de flujos)"
    echo -e "  ${COLOR_BOLD_CYAN}13)${COLOR_RESET} Instalar OpenClaw (asistente IA - solo VPN)"
    echo ""
    print_separator
    echo ""
    echo -e "  ${COLOR_BOLD_GREEN}A)${COLOR_RESET}  Instalación completa automática (1 → 10)"
    echo -e "  ${COLOR_BOLD_WHITE}I)${COLOR_RESET}  Información del sistema"
    echo -e "  ${COLOR_BOLD_RED}Q)${COLOR_RESET}  Salir"
    echo ""
    print_separator
    echo ""
}

# Función helper para ejecutar script local o remoto
run_script() {
    local script_name="$1"

    if [[ "$REMOTE_INSTALL" == "true" ]]; then
        local REPO_RAW="https://raw.githubusercontent.com/JaimeCruzH/vpsfacil/main"
        bash <(curl -sSL "${REPO_RAW}/${script_name}")
    else
        bash "${SCRIPT_DIR}/${script_name}"
    fi
}

# Función: mostrar info del sistema actual
show_system_info() {
    print_header "Información del Sistema"

    echo -e "  ${COLOR_BOLD_WHITE}Sistema:${COLOR_RESET}"
    echo -e "    OS:      $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo -e "    Kernel:  $(uname -r)"
    echo -e "    CPU:     $(nproc) cores"
    echo -e "    RAM:     $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "    Disco:   $(df -h / | awk 'NR==2 {print $4}') disponible de $(df -h / | awk 'NR==2 {print $2}')"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Red:${COLOR_RESET}"
    echo -e "    IP Pública: $(get_public_ip)"
    echo -e "    Hostname:   $(hostname)"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Configuración VPSfacil:${COLOR_RESET}"
    echo -e "    Dominio:     ${COLOR_CYAN}${DOMAIN}${COLOR_RESET}"
    echo -e "    Usuario:     ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}"
    echo -e "    Apps en:     ${COLOR_CYAN}${APPS_DIR}${COLOR_RESET}"
    echo -e "    URL N8N:     ${COLOR_CYAN}${URL_N8N}${COLOR_RESET}"
    echo -e "    URL Files:   ${COLOR_CYAN}${URL_FILEBROWSER}${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Docker:${COLOR_RESET}"
    if command_exists docker; then
        echo -e "    Versión:  $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')"
        echo -e "    Estado:   $(systemctl is-active docker 2>/dev/null || echo 'no instalado')"
    else
        echo -e "    Estado:   ${COLOR_YELLOW}No instalado${COLOR_RESET}"
    fi
    echo ""
    echo -e "  ${COLOR_BOLD_WHITE}Tailscale:${COLOR_RESET}"
    if command_exists tailscale; then
        local ts_ip
        ts_ip=$(tailscale ip -4 2>/dev/null || echo "No conectado")
        echo -e "    IP VPN:   ${COLOR_CYAN}${ts_ip}${COLOR_RESET}"
        echo -e "    Estado:   $(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4 || echo 'desconocido')"
    else
        echo -e "    Estado:   ${COLOR_YELLOW}No instalado${COLOR_RESET}"
    fi
    echo ""

    wait_for_user "Presiona Enter para volver al menú..."
}

# ============================================================
# LOOP PRINCIPAL DEL MENÚ
# ============================================================
while true; do
    show_main_menu
    echo -ne "${PREFIX_PROMPT} Selecciona una opción: "
    read -r opcion
    opcion="${opcion//$'\r'/}"  # strip CRLF artifacts

    case "${opcion^^}" in
        1)  run_script "scripts/00_precheck.sh" ;;
        2)  run_script "scripts/01_create_user.sh" ;;
        3)  run_script "scripts/02_secure_ssh.sh" ;;
        4)  run_script "scripts/03_install_firewall.sh" ;;
        5)  run_script "scripts/04_install_docker.sh" ;;
        6)  run_script "scripts/05_install_tailscale.sh" ;;
        7)  run_script "scripts/06_setup_certificates.sh" ;;
        8)  run_script "scripts/07_setup_dns.sh" ;;
        9)  run_script "scripts/08_install_portainer.sh" ;;
        10) run_script "scripts/09_install_kopia.sh" ;;
        11) run_script "scripts/10_install_filebrowser.sh" ;;
        12) run_script "apps/n8n.sh" ;;
        13) run_script "apps/openclaw.sh" ;;

        A)  # Instalación completa automática (FASE A + FASE B)
            print_header "Instalación Automática - FASE A"
            log_warning "Se instalarán todos los componentes core en 2 fases:"
            log_info    "  FASE A (ahora):     Pasos 1-3 + Tailscale (como root)"
            log_info    "  FASE B (después):   Pasos 4, 6-11 (como usuario admin)"
            echo ""
            if confirm "¿Iniciar instalación automática?"; then

                # ============================================================
                # FASE A: Recolectar inputs y ejecutar pasos 1-3, 5
                # ============================================================

                # 1. Recolectar TODOS los inputs upfront
                collect_all_inputs

                echo ""
                log_step "FASE A: Instalación Inicial (como root)"
                echo ""

                # 2. Ejecutar pasos 1-3 (como root)
                log_process "Paso 1: Pre-verificaciones..."
                run_script "scripts/00_precheck.sh" || {
                    log_error "Paso 1 falló. Abortando."
                    exit 1
                }

                log_process "Paso 2: Crear usuario admin..."
                run_script "scripts/01_create_user.sh" || {
                    log_error "Paso 2 falló. Abortando."
                    exit 1
                }

                log_process "Paso 3: Seguridad SSH..."
                run_script "scripts/02_secure_ssh.sh" || {
                    log_error "Paso 3 falló. Abortando."
                    exit 1
                }

                # 3. Ejecutar paso 5 (Tailscale - necesita usuario creado)
                log_process "Paso 5: Instalar y configurar Tailscale..."
                run_script "scripts/05_install_tailscale.sh" || {
                    log_error "Paso 5 falló. Abortando."
                    exit 1
                }

                # ============================================================
                # INSTRUCCIONES PARA FASE B
                # ============================================================
                echo ""
                echo ""
                print_separator
                echo ""
                log_success "¡FASE A Completada!"
                echo ""
                echo -e "  ${COLOR_BOLD_WHITE}Próximo paso:${COLOR_RESET}"
                echo ""
                windows_instruction "CONEXIÓN PARA FASE B (IMPORTANTE)

1. En tu PC Windows, abre Bitvise SSH Client

2. Configura la conexión:
   ├─ Host:                TU_VPS_IP (la misma de ahora)
   ├─ Port:                22 (o el puerto que configuraste)
   ├─ Username:            ${COLOR_CYAN}${ADMIN_USER}${COLOR_RESET}
   └─ Initial method:      Public key (usar la clave que ya tienes)

3. Haz clic en 'Login'

4. Una vez conectado, abre una terminal (New Terminal Console)

5. Ejecuta estos comandos:
   ${COLOR_BOLD_GREEN}cd ~/vpsfacil${COLOR_RESET}
   ${COLOR_BOLD_GREEN}bash scripts/install_core.sh${COLOR_RESET}

6. El script ejecutará los pasos 4-11 sin interrupciones
   (Firewall, Docker, Certificados, DNS, Portainer, Kopia, File Browser)

${COLOR_BOLD_YELLOW}Tiempo estimado FASE B: 15-20 minutos${COLOR_RESET}"
                echo ""
                print_separator
                echo ""
            fi
            wait_for_user
            ;;

        I)  show_system_info ;;

        Q)
            echo ""
            log_info "Saliendo de VPSfacil. ¡Hasta pronto!"
            echo ""
            exit 0
            ;;

        *)
            log_warning "Opción inválida: '${opcion}'. Elige un número del 1 al 13 o A, I, Q."
            sleep 2
            ;;
    esac

    # Pausa entre pasos para que el usuario pueda leer el resultado
    echo ""
    wait_for_user "Presiona Enter para volver al menú principal..."
done
