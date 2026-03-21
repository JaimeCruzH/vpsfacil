#!/bin/bash
# ============================================================
# lib/progress.sh — Gestión de progreso de instalación
# VPSfacil - Sistema Automatizado de Instalación en VPS
# ============================================================

# Variables globales
readonly PROGRESS_LOG="/tmp/vpsfacil_progress.log"
readonly PROGRESS_LOCK="/tmp/vpsfacil_progress.lock"

# Array con los 11 pasos de instalación
declare -gA CORE_STEPS=(
    [1]="Pre-verificaciones del Sistema"
    [2]="Crear Usuario Administrador"
    [3]="Firewall UFW"
    [4]="Docker & Docker Compose"
    [5]="Tailscale VPN"
    [6]="Certificados SSL"
    [7]="DNS Cloudflare"
    [8]="Portainer"
    [9]="Kopia Backup"
    [10]="File Browser"
    [11]="Finalizar: Permisos y SSH"
)

# ============================================================
# INICIALIZAR LOG DE PROGRESO
# ============================================================
progress_init() {
    if [[ -f "$PROGRESS_LOG" ]]; then
        log_info "Detectada instalación previa. Continuando desde donde se quedó..."
    else
        > "$PROGRESS_LOG"
        log_info "Iniciando nuevo registro de progreso"
    fi
}

# ============================================================
# VERIFICAR SI UN PASO YA FUE COMPLETADO
# ============================================================
progress_is_completed() {
    local step_num="$1"
    if [[ -f "$PROGRESS_LOG" ]]; then
        grep -q "^PASO=${step_num}|.*STATUS=completado" "$PROGRESS_LOG" 2>/dev/null
        return $?
    fi
    return 1
}

# ============================================================
# MARCAR UN PASO COMO INICIADO
# ============================================================
progress_start_step() {
    local step_num="$1"
    local start_epoch=$(date +%s)
    export "STEP_${step_num}_START=$start_epoch"
}

# ============================================================
# MARCAR UN PASO COMO COMPLETADO
# ============================================================
progress_complete_step() {
    local step_num="$1"
    local step_name="${CORE_STEPS[$step_num]}"

    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local end_epoch=$(date +%s)
    local start_var="STEP_${step_num}_START"
    local start_epoch="${!start_var:-0}"

    local duration=0
    if [[ $start_epoch -gt 0 ]]; then
        duration=$((end_epoch - start_epoch))
    fi

    local duration_str=$(printf "%dm%02ds" $((duration / 60)) $((duration % 60)))

    echo "PASO=$step_num|NOMBRE=$step_name|STATUS=completado|FIN=$end_time|DURACION=$duration_str" >> "$PROGRESS_LOG"

    unset "STEP_${step_num}_START"
}

# ============================================================
# MARCAR UN PASO COMO FALLIDO
# ============================================================
progress_fail_step() {
    local step_num="$1"
    local step_name="${CORE_STEPS[$step_num]}"
    local error_msg="${2:-Unknown error}"

    local fail_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo "PASO=$step_num|NOMBRE=$step_name|STATUS=fallido|FALLO=$fail_time|ERROR=$error_msg" >> "$PROGRESS_LOG"

    unset "STEP_${step_num}_START"
}

# ============================================================
# OBTENER DURACIÓN TOTAL
# ============================================================
progress_get_total_duration() {
    if [[ ! -f "$PROGRESS_LOG" ]]; then
        echo "0"
        return
    fi

    local total_seconds=0
    while IFS='|' read -r step name status rest; do
        if [[ "$status" == "STATUS=completado" ]]; then
            local dur_field=""
            dur_field=$(echo "$rest" | grep -o "DURACION=[^|]*" || echo "")
            if [[ "$dur_field" =~ DURACION=([0-9]+)m([0-9]+)s ]]; then
                local mins="${BASH_REMATCH[1]}"
                local secs="${BASH_REMATCH[2]}"
                total_seconds=$((total_seconds + mins * 60 + secs))
            fi
        fi
    done < "$PROGRESS_LOG"

    echo "$total_seconds"
}

# ============================================================
# MOSTRAR PROGRESO VISUAL
# ============================================================
progress_show() {
    local completed_count=0
    local total_count=11

    local completed_steps=""
    if [[ -f "$PROGRESS_LOG" ]]; then
        if grep -q "STATUS=completado" "$PROGRESS_LOG" 2>/dev/null; then
            completed_count=$(grep "STATUS=completado" "$PROGRESS_LOG" 2>/dev/null | wc -l | tr -d ' ')
        fi
        completed_steps=$(grep "STATUS=completado" "$PROGRESS_LOG" 2>/dev/null | cut -d'|' -f1 | sed 's/PASO=//' | tr '\n' ' ' 2>/dev/null || echo "")
    fi

    local percentage=$((completed_count * 100 / total_count))

    # Barra de progreso ASCII
    local bar_length=30
    local filled=$((percentage * bar_length / 100))
    local empty=$((bar_length - filled))

    local progress_bar=""
    for ((i = 0; i < filled; i++)); do
        progress_bar+="█"
    done
    for ((i = 0; i < empty; i++)); do
        progress_bar+="░"
    done

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    printf "║  Instalación VPSfacil: Progreso %d/%d (%d%%)                  ║\n" "$completed_count" "$total_count" "$percentage"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║                                                               ║"
    printf "║  [%s] %d%%                                ║\n" "$progress_bar" "$percentage"
    echo "║                                                               ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"

    for step_num in 1 2 3 4 5 6 7 8 9 10 11; do
        local step_name="${CORE_STEPS[$step_num]}"
        local status_icon="⏸"
        local info="[en espera]"

        if [[ " $completed_steps " =~ " $step_num " ]]; then
            status_icon="✓"
            local duration=$(grep "^PASO=$step_num|" "$PROGRESS_LOG" 2>/dev/null | grep "STATUS=completado" 2>/dev/null | tail -1 | grep -o "DURACION=[^|]*" 2>/dev/null | cut -d'=' -f2 || echo "")
            if [[ -n "$duration" ]]; then
                info="[completado $duration]"
            else
                info="[completado]"
            fi
        fi

        printf "║  %-1s Paso %-2d: %-35s %s  ║\n" "$status_icon" "$step_num" "$step_name" "$info"
    done

    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
}

# ============================================================
# LIMPIAR PROGRESO
# ============================================================
progress_reset() {
    rm -f "$PROGRESS_LOG"
    rm -f "$PROGRESS_LOCK"
    log_info "Registro de progreso limpiado"
}
