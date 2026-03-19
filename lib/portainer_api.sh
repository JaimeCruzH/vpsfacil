#!/bin/bash
# ============================================================
# lib/portainer_api.sh — Wrappers REST API de Portainer
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Funciones disponibles:
#   portainer_login         → obtiene JWT token
#   portainer_endpoint_id   → obtiene ID del entorno Docker local
#   portainer_stack_deploy  → crea o actualiza un stack
#   portainer_save_creds    → guarda credenciales para uso posterior
#   portainer_load_creds    → carga credenciales guardadas
#
# Requiere: curl, jq (instalados en paso 1)
# ============================================================

# URL local de Portainer (accesible desde el propio servidor)
PORTAINER_URL="https://localhost:9443"
PORTAINER_CREDS_FILE="${APPS_DIR}/portainer/.credentials"

# ============================================================
# Guardar credenciales de Portainer para uso por los scripts
# ============================================================
portainer_save_creds() {
    local username="$1"
    local password="$2"

    mkdir -p "$(dirname "$PORTAINER_CREDS_FILE")"
    # printf '%q' escapes $, spaces y caracteres especiales para que
    # el archivo pueda ser sourced sin errores de "unbound variable"
    printf 'PORTAINER_USER=%q\n' "$username" >  "$PORTAINER_CREDS_FILE"
    printf 'PORTAINER_PASS=%q\n' "$password" >> "$PORTAINER_CREDS_FILE"
    chmod 600 "$PORTAINER_CREDS_FILE"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$PORTAINER_CREDS_FILE"
}

# ============================================================
# Cargar credenciales guardadas
# ============================================================
portainer_load_creds() {
    if [[ ! -f "$PORTAINER_CREDS_FILE" ]]; then
        log_error "No se encontraron credenciales de Portainer."
        log_info  "Ejecuta primero el paso 9 (Instalar Portainer)."
        return 1
    fi
    # shellcheck source=/dev/null
    source "$PORTAINER_CREDS_FILE"
}

# ============================================================
# Autenticar y obtener JWT token
# Uso: jwt=$(portainer_login "admin" "password")
# ============================================================
portainer_login() {
    local username="$1"
    local password="$2"

    local body
    body=$(jq -n --arg u "$username" --arg p "$password" \
        '{"username":$u,"password":$p}')

    local response
    response=$(curl -sk -X POST "${PORTAINER_URL}/api/auth" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null)

    local jwt
    jwt=$(echo "$response" | jq -r '.jwt // ""' 2>/dev/null)

    if [[ -z "$jwt" ]]; then
        log_error "No se pudo autenticar con Portainer."
        log_info  "Verifica que Portainer esté corriendo y las credenciales sean correctas."
        return 1
    fi

    echo "$jwt"
}

# ============================================================
# Obtener el ID del entorno Docker local (normalmente es 1)
# Uso: endpoint_id=$(portainer_endpoint_id "$jwt")
# ============================================================
portainer_endpoint_id() {
    local jwt="$1"

    local response
    response=$(curl -sk -X GET "${PORTAINER_URL}/api/endpoints" \
        -H "Authorization: Bearer ${jwt}" 2>/dev/null)

    # Tomar el primer endpoint local
    echo "$response" | jq -r '.[0].Id // 1' 2>/dev/null || echo "1"
}

# ============================================================
# Crear o actualizar un stack en Portainer vía API
#
# Uso:
#   portainer_stack_deploy "$jwt" "$endpoint_id" "nombre-stack" "$compose_content"
#
# Si el stack ya existe → lo actualiza
# Si no existe → lo crea nuevo
# ============================================================
portainer_stack_deploy() {
    local jwt="$1"
    local endpoint_id="$2"
    local stack_name="$3"
    local compose_content="$4"

    # Verificar si el stack ya existe
    local stacks
    stacks=$(curl -sk -X GET "${PORTAINER_URL}/api/stacks" \
        -H "Authorization: Bearer ${jwt}" 2>/dev/null)

    local existing_id
    existing_id=$(echo "$stacks" | \
        jq -r --arg name "$stack_name" \
        '.[] | select(.Name==$name) | .Id' 2>/dev/null)

    local body
    body=$(jq -n \
        --arg name "$stack_name" \
        --arg content "$compose_content" \
        '{name:$name, stackFileContent:$content}')

    if [[ -n "$existing_id" ]]; then
        # Actualizar stack existente
        local update_body
        update_body=$(jq -n \
            --arg content "$compose_content" \
            '{stackFileContent:$content, prune:false, pullImage:true}')

        curl -sk -X PUT \
            "${PORTAINER_URL}/api/stacks/${existing_id}?endpointId=${endpoint_id}" \
            -H "Authorization: Bearer ${jwt}" \
            -H "Content-Type: application/json" \
            -d "$update_body" > /dev/null 2>&1

        log_success "Stack '${stack_name}' actualizado en Portainer ✓"
    else
        # Crear stack nuevo
        local result
        result=$(curl -sk -X POST \
            "${PORTAINER_URL}/api/stacks/create/standalone/string?endpointId=${endpoint_id}" \
            -H "Authorization: Bearer ${jwt}" \
            -H "Content-Type: application/json" \
            -d "$body" 2>/dev/null)

        local new_id
        new_id=$(echo "$result" | jq -r '.Id // ""' 2>/dev/null)

        if [[ -z "$new_id" ]]; then
            log_warning "No se pudo crear el stack via API. Desplegando con docker compose..."
            return 1
        fi

        log_success "Stack '${stack_name}' creado en Portainer (ID: ${new_id}) ✓"
    fi

    return 0
}

# ============================================================
# Función de conveniencia: login + deploy en un solo paso
# Usa las credenciales guardadas automáticamente
#
# Uso:
#   portainer_deploy_stack "nombre-stack" "$compose_content"
# ============================================================
portainer_deploy_stack() {
    local stack_name="$1"
    local compose_content="$2"

    # Cargar credenciales
    if ! portainer_load_creds; then
        return 1
    fi

    # Autenticar
    local jwt
    jwt=$(portainer_login "$PORTAINER_USER" "$PORTAINER_PASS") || return 1

    # Obtener endpoint
    local endpoint_id
    endpoint_id=$(portainer_endpoint_id "$jwt")

    # Desplegar
    portainer_stack_deploy "$jwt" "$endpoint_id" "$stack_name" "$compose_content"
}
