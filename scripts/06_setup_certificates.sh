#!/bin/bash
# ============================================================
# scripts/06_setup_certificates.sh — Certificados SSL
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Qué hace este script:
#   1. Guía al usuario paso a paso para obtener un
#      Cloudflare Origin Certificate (válido 15 años)
#   2. Pide al usuario que pegue el certificado y la clave
#      directamente en la terminal
#   3. Guarda los archivos en /home/ADMIN/apps/certs/
#   4. Aplica permisos correctos
#   5. Descarga el CA Bundle de Cloudflare
#
# Por qué Cloudflare Origin Certificate:
#   - Gratuito y válido 15 años (sin renovaciones)
#   - Validado vía DNS (no necesita acceso público al servidor)
#   - El navegador confía en él (CA de Cloudflare reconocida)
#   - Un solo certificado wildcard cubre todas las subapps
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
print_header "Paso 7 de 10 — Configurar Certificados SSL"
# ============================================================

check_root

log_info "Los certificados SSL permiten que tus apps usen HTTPS,"
log_info "lo que el navegador requiere aunque estés en VPN privada."
echo ""
log_info "Usaremos un Cloudflare Origin Certificate que cubre:"
echo -e "   ${COLOR_CYAN}*.vpn.${DOMAIN}${COLOR_RESET}"
echo ""
log_info "Con este certificado tienes HTTPS en todas tus apps"
log_info "sin necesidad de renovarlo por 15 años."
echo ""

# Verificar que existe la carpeta de certs
mkdir -p "${CERTS_DIR}"
chown "${ADMIN_USER}:${ADMIN_USER}" "${CERTS_DIR}"
chmod 755 "${CERTS_DIR}"

# ============================================================
# VERIFICAR SI YA EXISTEN CERTIFICADOS
# ============================================================
log_step "Verificando certificados existentes"

if [[ -f "${CERT_FILE}" && -f "${CERT_KEY}" ]]; then
    log_info "Ya existen archivos de certificado:"
    log_info "  Cert: ${CERT_FILE}"
    log_info "  Key:  ${CERT_KEY}"

    # Verificar fecha de expiración
    EXPIRY=$(openssl x509 -enddate -noout -in "${CERT_FILE}" 2>/dev/null \
        | cut -d= -f2 || echo "desconocida")
    log_info "  Expira: ${EXPIRY}"

    if confirm "¿Deseas reemplazar los certificados existentes?"; then
        log_info "Creando backup del certificado actual..."
        cp "${CERT_FILE}" "${CERT_FILE}.backup.$(date +%Y%m%d)"
        cp "${CERT_KEY}" "${CERT_KEY}.backup.$(date +%Y%m%d)"
        log_success "Backup creado ✓"
    else
        log_info "Certificados existentes conservados. Continuando..."
        exit 0
    fi
fi

# ============================================================
# GUÍA PASO A PASO: OBTENER CERTIFICADO EN CLOUDFLARE
# ============================================================
log_step "Guía para obtener el Cloudflare Origin Certificate"

echo ""
echo -e "${COLOR_BOLD_YELLOW}╔══ INSTRUCCIONES CLOUDFLARE ══════════════════════════════════╗${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  Sigue estos pasos en tu navegador Windows:                  ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  1. Ve a: https://dash.cloudflare.com                        ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  2. Selecciona tu dominio: ${DOMAIN}${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  3. En el menú izquierdo: SSL/TLS → Origin Server            ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  4. Haz clic en: 'Create Certificate'                       ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  5. En 'Hostnames' agrega EXACTAMENTE:                      ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║     *.vpn.${DOMAIN}${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  6. En 'Certificate Validity': selecciona 15 years           ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  7. Haz clic en 'Create'                                    ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  8. Verás dos bloques de texto:                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║     - Origin Certificate (el certificado)                   ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║     - Private Key (la clave privada)                         ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║  ⚠ NO CIERRES esa pantalla hasta que hayas pegado           ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║    ambos textos aquí. Cloudflare no vuelve a mostrar         ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║    la clave privada.                                         ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}║                                                              ║${COLOR_RESET}"
echo -e "${COLOR_BOLD_YELLOW}╚══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
echo ""

wait_for_user "Presiona Enter cuando tengas el certificado y la clave listos para copiar..."

# ============================================================
# PEDIR EL CERTIFICADO (el usuario lo pega)
# ============================================================
log_step "Pegando el certificado SSL"

echo ""
log_info "Copia el contenido de 'Origin Certificate' de Cloudflare."
log_info "Empieza con: -----BEGIN CERTIFICATE-----"
log_info "Termina con: -----END CERTIFICATE-----"
echo ""
log_info "Pega el certificado abajo y presiona ENTER + CTRL+D cuando termines:"
echo ""

# Leer el certificado (múltiples líneas, termina con Ctrl+D)
CERT_CONTENT=""
while IFS= read -r linea; do
    CERT_CONTENT+="${linea}"$'\n'
done

# Validar que tiene formato de certificado
if ! echo "$CERT_CONTENT" | grep -q "BEGIN CERTIFICATE"; then
    log_error "El texto pegado no parece un certificado válido"
    log_info  "Debe comenzar con: -----BEGIN CERTIFICATE-----"
    log_info  "Ejecuta este paso nuevamente"
    exit 1
fi

# Guardar certificado
echo "$CERT_CONTENT" > "${CERT_FILE}"
log_success "Certificado guardado ✓"

# ============================================================
# PEDIR LA CLAVE PRIVADA
# ============================================================
log_step "Pegando la clave privada"

echo ""
log_info "Ahora copia el contenido de 'Private Key' de Cloudflare."
log_info "Empieza con: -----BEGIN PRIVATE KEY-----"
log_info "Termina con: -----END PRIVATE KEY-----"
echo ""
log_warning "La clave privada es confidencial. Se guardará con permisos"
log_warning "restrictivos (solo lectura del propietario)."
echo ""
log_info "Pega la clave privada abajo y presiona ENTER + CTRL+D:"
echo ""

KEY_CONTENT=""
while IFS= read -r linea; do
    KEY_CONTENT+="${linea}"$'\n'
done

# Validar formato de clave privada
if ! echo "$KEY_CONTENT" | grep -qE "BEGIN (RSA |EC |)PRIVATE KEY"; then
    log_error "El texto pegado no parece una clave privada válida"
    log_info  "Debe comenzar con: -----BEGIN PRIVATE KEY-----"
    log_info  "Ejecuta este paso nuevamente"
    exit 1
fi

# Guardar clave privada
echo "$KEY_CONTENT" > "${CERT_KEY}"
log_success "Clave privada guardada ✓"

# ============================================================
# DESCARGAR CA BUNDLE DE CLOUDFLARE
# ============================================================
log_step "Descargando CA Bundle de Cloudflare"

log_process "Descargando certificado CA de Cloudflare Origin..."

if curl -fsSL \
    "https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem" \
    -o "${CERT_CA}" 2>/dev/null; then
    log_success "CA Bundle descargado ✓"
else
    log_warning "No se pudo descargar el CA Bundle automáticamente"
    log_info    "Puedes descargarlo manualmente desde:"
    log_info    "https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem"
    # Crear archivo vacío para no romper referencias
    touch "${CERT_CA}"
fi

# ============================================================
# APLICAR PERMISOS CORRECTOS
# ============================================================
log_step "Aplicando permisos de seguridad"

# El certificado puede ser leído por el grupo
chmod 644 "${CERT_FILE}"
chmod 644 "${CERT_CA}"

# La clave privada: solo lectura del propietario
chmod 600 "${CERT_KEY}"

# Propiedad al usuario admin
chown "${ADMIN_USER}:${ADMIN_USER}" "${CERTS_DIR}"
chown "${ADMIN_USER}:${ADMIN_USER}" "${CERT_FILE}" "${CERT_KEY}"
[[ -f "${CERT_CA}" ]] && chown "${ADMIN_USER}:${ADMIN_USER}" "${CERT_CA}"

log_success "Permisos aplicados ✓"
log_info    "  Certificado: 644 (lectura pública)"
log_info    "  Clave privada: 600 (solo ${ADMIN_USER})"

# ============================================================
# VERIFICAR CERTIFICADO
# ============================================================
log_step "Verificando certificado"

CERT_SUBJECT=$(openssl x509 -subject -noout -in "${CERT_FILE}" 2>/dev/null || echo "No se pudo leer")
CERT_EXPIRY=$(openssl x509 -enddate -noout -in "${CERT_FILE}" 2>/dev/null | cut -d= -f2 || echo "desconocida")
CERT_ISSUER=$(openssl x509 -issuer -noout -in "${CERT_FILE}" 2>/dev/null | grep -oP 'O=\K[^,]+' || echo "desconocido")

echo ""
log_info "Información del certificado:"
echo -e "   ${COLOR_BOLD_WHITE}Sujeto:${COLOR_RESET}  ${CERT_SUBJECT}"
echo -e "   ${COLOR_BOLD_WHITE}Emisor:${COLOR_RESET}  ${CERT_ISSUER}"
echo -e "   ${COLOR_BOLD_WHITE}Expira:${COLOR_RESET}  ${CERT_EXPIRY}"
echo ""

# Verificar que coincide con el dominio
if openssl x509 -text -noout -in "${CERT_FILE}" 2>/dev/null | grep -q "vpn.${DOMAIN}"; then
    log_success "Certificado válido para *.vpn.${DOMAIN} ✓"
else
    log_warning "No se pudo verificar que el certificado cubra *.vpn.${DOMAIN}"
    log_info    "Verifica en Cloudflare que usaste el hostname correcto"
fi

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
print_separator
echo ""
log_success "Certificados SSL configurados exitosamente"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Archivos creados:${COLOR_RESET}"
echo -e "    ${COLOR_CYAN}${CERT_FILE}${COLOR_RESET}"
echo -e "    ${COLOR_CYAN}${CERT_KEY}${COLOR_RESET} (solo lectura, 600)"
echo -e "    ${COLOR_CYAN}${CERT_CA}${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD_WHITE}Validez:${COLOR_RESET}"
echo -e "    ${COLOR_CYAN}${CERT_EXPIRY}${COLOR_RESET}"
echo -e "    Sin renovaciones necesarias hasta entonces"
echo ""
log_info "Próximo paso: Configurar DNS en Cloudflare (opción 8)"
echo ""
