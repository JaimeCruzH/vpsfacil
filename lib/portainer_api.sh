#!/bin/bash
# ============================================================
# lib/portainer_api.sh — Wrappers REST API de Portainer
# VPSfacil - Sistema Automatizado de Instalación en VPS
#
# Funciones disponibles:
#   portainer_login              → obtiene JWT token
#   portainer_endpoint_id        → obtiene ID del entorno Docker local
#   portainer_ensure_endpoint    → crea entorno local si no existe
#   portainer_stack_deploy       → crea o actualiza un stack
#   portainer_save_creds         → guarda credenciales para uso posterior
#   portainer_load_creds         → carga credenciales guardadas
#   portainer_deploy_stack       → conveniencia: login + deploy
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
        return 1
    fi

    echo "$jwt"
}

# ============================================================
# Asegurar que existe un entorno Docker local en Portainer
# En versiones recientes de Portainer CE, el entorno local no
# siempre se crea automáticamente después del admin/init.
#
# Uso: portainer_ensure_endpoint "$jwt"
# ============================================================
portainer_ensure_endpoint() {
    local jwt="$1"

    # Verificar si ya existe algún endpoint
    local endpoints
    endpoints=$(curl -sk -X GET "${PORTAINER_URL}/api/endpoints" \
        -H "Authorization: Bearer ${jwt}" 2>/dev/null)

    local count
    count=$(echo "$endpoints" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        return 0
    fi

    # No hay endpoints — crear el entorno Docker local
    log_process "Inicializando entorno Docker local en Portainer..."

    local result
    result=$(curl -sk -X POST "${PORTAINER_URL}/api/endpoints" \
        -H "Authorization: Bearer ${jwt}" \
        -H "Content-Type: multipart/form-data" \
        -F "Name=local" \
        -F "EndpointCreationType=1" \
        2>/dev/null)

    local new_id
    new_id=$(echo "$result" | jq -r '.Id // ""' 2>/dev/null)

    if [[ -n "$new_id" ]]; then
        log_success "Entorno Docker local creado en Portainer (ID: ${new_id}) ✓"
    else
        log_warning "No se pudo crear el entorno Docker local automáticamente"
    fi
}

# ============================================================
# Obtener el ID del entorno Docker local
# Uso: endpoint_id=$(portainer_endpoint_id "$jwt")
# ============================================================
portainer_endpoint_id() {
    local jwt="$1"

    local response
    response=$(curl -sk -X GET "${PORTAINER_URL}/api/endpoints" \
        -H "Authorization: Bearer ${jwt}" 2>/dev/null)

    local id
    id=$(echo "$response" | jq -r '.[0].Id // ""' 2>/dev/null)

    if [[ -z "$id" ]]; then
        echo ""
        return 1
    fi

    echo "$id"
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

    # Validar que tenemos endpoint_id
    if [[ -z "$endpoint_id" ]]; then
        log_warning "No hay entorno Docker configurado en Portainer"
        return 1
    fi

    # Verificar si el stack ya existe
    local stacks
    stacks=$(curl -sk -X GET "${PORTAINER_URL}/api/stacks" \
        -H "Authorization: Bearer ${jwt}" 2>/dev/null)

    local existing_id
    existing_id=$(echo "$stacks" | \
        jq -r --arg name "$stack_name" \
        '.[] | select(.Name==$name) | .Id' 2>/dev/null)

    if [[ -n "$existing_id" ]]; then
        # Actualizar stack existente
        local update_body
        update_body=$(jq -n \
            --arg content "$compose_content" \
            '{stackFileContent:$content, prune:false, pullImage:true}')

        local update_result
        update_result=$(curl -sk -X PUT \
            "${PORTAINER_URL}/api/stacks/${existing_id}?endpointId=${endpoint_id}" \
            -H "Authorization: Bearer ${jwt}" \
            -H "Content-Type: application/json" \
            -d "$update_body" 2>/dev/null)

        local updated_id
        updated_id=$(echo "$update_result" | jq -r '.Id // ""' 2>/dev/null)

        if [[ -n "$updated_id" ]]; then
            log_success "Stack '${stack_name}' actualizado en Portainer ✓"
            return 0
        else
            local update_err
            update_err=$(echo "$update_result" | jq -r '.message // .details // "error desconocido"' 2>/dev/null)
            log_warning "Error actualizando stack '${stack_name}': ${update_err}"
            return 1
        fi
    else
        # Crear stack nuevo
        local body
        body=$(jq -n \
            --arg name "$stack_name" \
            --arg content "$compose_content" \
            '{name:$name, stackFileContent:$content}')

        local result
        result=$(curl -sk -X POST \
            "${PORTAINER_URL}/api/stacks/create/standalone/string?endpointId=${endpoint_id}" \
            -H "Authorization: Bearer ${jwt}" \
            -H "Content-Type: application/json" \
            -d "$body" 2>/dev/null)

        local new_id
        new_id=$(echo "$result" | jq -r '.Id // ""' 2>/dev/null)

        if [[ -n "$new_id" ]]; then
            log_success "Stack '${stack_name}' creado en Portainer (ID: ${new_id}) ✓"
            return 0
        else
            local err_msg
            err_msg=$(echo "$result" | jq -r '.message // .details // "error desconocido"' 2>/dev/null)
            log_warning "Error creando stack '${stack_name}': ${err_msg}"
            return 1
        fi
    fi
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

    # Asegurar que existe el entorno Docker local
    portainer_ensure_endpoint "$jwt"

    # Obtener endpoint
    local endpoint_id
    endpoint_id=$(portainer_endpoint_id "$jwt") || return 1

    # Desplegar
    portainer_stack_deploy "$jwt" "$endpoint_id" "$stack_name" "$compose_content"
}
