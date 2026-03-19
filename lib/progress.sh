#!/bin/bash
# ============================================================
# lib/progress.sh — Gestión de progreso de instalación FASE B
# VPSfacil - Sistema Automatizado de Instalación en VPS
# ============================================================

# Variables globales
readonly PROGRESS_LOG="/tmp/vpsfacil_core_progress.log"
readonly PROGRESS_LOCK="/tmp/vpsfacil_core_progress.lock"

# Array con los pasos core (paso_num, nombre)
declare -gA CORE_STEPS=(
    [4]="Firewall UFW"
    [6]="Docker & Docker Compose"
    [7]="Certificados SSL (Let's Encrypt)"
    [8]="DNS Cloudflare"
    [9]="Portainer"
    [10]="Kopia Backup"
    [11]="File Browser"
)

# ============================================================
# INICIALIZAR LOG DE PROGRESO
# ============================================================
progress_init() {
    # Si el log ya existe, es una reconexión
    if [[ -f "$PROGRESS_LOG" ]]; then
        log_info "Detectada instalación previa. Continuando desde donde se quedó..."
    else
        # Crear log vacío
        > "$PROGRESS_LOG"
        log_info "Iniciando nuevo registro de progreso"
    fi
}

# ============================================================
# MARCAR UN PASO COMO INICIADO
# ============================================================
progress_start_step() {
    local step_num="$1"
    local step_name="${CORE_STEPS[$step_num]}"

    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local start_epoch=$(date +%s)

    # Guardar timestamp de inicio en variable temporal
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
    local start_epoch="${STEP_${step_num}_START:-0}"

    local duration=0
    if [[ $start_epoch -gt 0 ]]; then
        duration=$((end_epoch - start_epoch))
    fi

    local duration_str=$(printf "%dm%02ds" $((duration / 60)) $((duration % 60)))

    # Agregar entrada al log
    echo "PASO=$step_num|NOMBRE=$step_name|STATUS=completado|INICIO=$start_time|FIN=$end_time|DURACION=$duration_str" >> "$PROGRESS_LOG"

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

    # Agregar entrada al log
    echo "PASO=$step_num|NOMBRE=$step_name|STATUS=fallido|FALLO=$fail_time|ERROR=$error_msg" >> "$PROGRESS_LOG"

    unset "STEP_${step_num}_START"
}

# ============================================================
# OBTENER LISTA DE PASOS COMPLETADOS
# ============================================================
progress_get_completed() {
    if [[ ! -f "$PROGRESS_LOG" ]]; then
        echo ""
        return
    fi

    grep "STATUS=completado" "$PROGRESS_LOG" | cut -d'|' -f1 | cut -d'=' -f2
}

# ============================================================
# OBTENER DURACIÓN TOTAL
# ============================================================
progress_get_total_duration() {
    if [[ ! -f "$PROGRESS_LOG" ]]; then
        echo "0"
        return
    fi

    # Calcular duración total de todos los pasos completados
    local total_seconds=0
    while IFS='|' read -r step name status inicio fin duracion; do
        if [[ "$status" == "STATUS=completado" && "$duracion" =~ ^DURACION=([0-9]+)m([0-9]+)s$ ]]; then
            local mins="${BASH_REMATCH[1]}"
            local secs="${BASH_REMATCH[2]}"
            total_seconds=$((total_seconds + mins * 60 + secs))
        fi
    done < "$PROGRESS_LOG"

    echo "$total_seconds"
}

# ============================================================
# MOSTRAR PROGRESO VISUAL
# ============================================================
progress_show() {
    local completed_count=0
    local total_count=7  # Pasos 4, 6, 7, 8, 9, 10, 11

    local completed_steps=""
    if [[ -f "$PROGRESS_LOG" ]]; then
        completed_steps=$(grep "STATUS=completado" "$PROGRESS_LOG" | cut -d'|' -f1 | cut -d'=' -f2 | tr '\n' ' ' || true)
        completed_count=$(echo "$completed_steps" | wc -w)
    fi

    # Calcular porcentaje
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

    # Mostrar encabezado
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  FASE B - Instalación Core: Progreso $completed_count/$total_count ($percentage%)     ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║                                                               ║"
    echo "║  [$progress_bar] $percentage%                   ║"
    echo "║                                                               ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Mostrar estado de cada paso
    for step_num in 4 6 7 8 9 10 11; do
        local step_name="${CORE_STEPS[$step_num]}"
        local status="⏸"
        local info="[en espera]"

        # Buscar si el paso está completado
        if [[ " $completed_steps " =~ " $step_num " ]]; then
            status="✓"
            local duration=$(grep "^PASO=$step_num|" "$PROGRESS_LOG" 2>/dev/null | grep "STATUS=completado" 2>/dev/null | tail -1 | grep -o "DURACION=[^|]*" 2>/dev/null | cut -d'=' -f2 || echo "")
            info="[completado en $duration]"
        fi

        printf "║  %-1s Paso %-2d: %-35s %s  ║\n" "$status" "$step_num" "$step_name" "$info"
    done

    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
}

# ============================================================
# LIMPIAR PROGRESO (para reintentos completos)
# ============================================================
progress_reset() {
    rm -f "$PROGRESS_LOG"
    rm -f "$PROGRESS_LOCK"
    log_info "Registro de progreso limpiado"
}
