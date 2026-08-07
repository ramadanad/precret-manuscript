#!/bin/bash

# main.sh - Orchestrate pipelines: func + anat (parallel), then coreg, then samsrf
# Usage: ./main.sh <BIDS_ROOT> <SUBJECT> [SESSION]
# Example: ./main.sh /home/dramadan/data/prf_bids sub-01 ses-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_functions.sh"

ARGS=("$@")
COMMAND_LINE="$(build_cmdline_string "$0" "${ARGS[@]}")"

if [[ ${#ARGS[@]} -lt 2 ]]; then
    echo "Error: <BIDS_ROOT> and <SUBJECT> are required"
    echo "Usage: $0 <BIDS_ROOT> <SUBJECT> [SESSION]"
    exit 1
fi

BIDS_ROOT="${ARGS[0]}"
SUBJECT="${ARGS[1]}"
SESSION="${ARGS[2]:-}"
SESSION_CONTEXT="${SESSION:-all-sessions}"

DEFAULT_PIPELINE_TIMEOUT_SECONDS="${DEFAULT_PIPELINE_TIMEOUT_SECONDS:-0}"
# Per-pipeline timeout overrides. A value of 0 disables timeout for that stage.
FUNC_PIPELINE_TIMEOUT_SECONDS="${FUNC_PIPELINE_TIMEOUT_SECONDS:-$DEFAULT_PIPELINE_TIMEOUT_SECONDS}"
ANAT_PIPELINE_TIMEOUT_SECONDS="${ANAT_PIPELINE_TIMEOUT_SECONDS:-$DEFAULT_PIPELINE_TIMEOUT_SECONDS}"
COREG_PIPELINE_TIMEOUT_SECONDS="${COREG_PIPELINE_TIMEOUT_SECONDS:-$DEFAULT_PIPELINE_TIMEOUT_SECONDS}"
SAMSRF_PIPELINE_TIMEOUT_SECONDS="${SAMSRF_PIPELINE_TIMEOUT_SECONDS:-$DEFAULT_PIPELINE_TIMEOUT_SECONDS}"
# Grace period between SIGTERM and SIGKILL when force-stopping lingering jobs.
PIPELINE_TERMINATION_GRACE_SECONDS="${PIPELINE_TERMINATION_GRACE_SECONDS:-30}"

init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "main" "$SESSION_CONTEXT" "$COMMAND_LINE" || exit 1
log_pipeline_run_start

LOG_DIR="$(dirname "$LOGFILE")"
# Track parallel jobs so we can fail fast and clean up all remaining work.
declare -a RUNNING_PIDS=()
declare -A PID_TO_NAME=()
declare -A PID_TO_LOGFILE=()

main_log() {
    printf '%s\n' "$*" | tee -a "$LOGFILE"
}

pipeline_log_path() {
    # Keep one per-pipeline log near the main log, then append into main log for one-stop review.
    local pipeline_name="$1"
    echo "$LOG_DIR/${SUBJECT}_${pipeline_name}.log"
}

build_pipeline_command() {
    local script="$1"
    local -n command_ref="$2"

    command_ref=("$script" "$BIDS_ROOT" "$SUBJECT")
    if [[ -n "$SESSION" ]]; then
        # func_pipeline expects a named flag, while the other pipelines use positional session.
        # Keep this branch explicit to match existing pipeline CLIs without changing them.
        if [[ $(basename "$script") == "func_pipeline.sh" ]]; then
            command_ref+=(--session "$SESSION")
        else
            command_ref+=("$SESSION")
        fi
    fi
}

run_pipeline_command() {
    local timeout_seconds="$1"
    shift

    if (( timeout_seconds > 0 )); then
        # timeout is optional so users can run long jobs without forced termination.
        if ! command -v timeout >/dev/null 2>&1; then
            echo "Error: timeout command not found, but a timeout was requested (${timeout_seconds}s)."
            return 1
        fi

        timeout --foreground --preserve-status --signal=TERM --kill-after="${PIPELINE_TERMINATION_GRACE_SECONDS}s" "${timeout_seconds}s" "$@"
    else
        "$@"
    fi
}

run_pipeline_detached() {
    local timeout_seconds="$1"
    local command_line="$2"

    # Start in a separate session when possible so we can terminate the whole process group.
    # This is important for container wrappers that spawn child processes.
    if command -v setsid >/dev/null 2>&1; then
        if (( timeout_seconds > 0 )); then
            setsid timeout --foreground --preserve-status --signal=TERM --kill-after="${PIPELINE_TERMINATION_GRACE_SECONDS}s" "${timeout_seconds}s" bash -lc "$command_line" &
        else
            setsid bash -lc "$command_line" &
        fi
    else
        if (( timeout_seconds > 0 )); then
            timeout --foreground --preserve-status --signal=TERM --kill-after="${PIPELINE_TERMINATION_GRACE_SECONDS}s" "${timeout_seconds}s" bash -lc "$command_line" &
        else
            bash -lc "$command_line" &
        fi
    fi
}

append_pipeline_log_to_main() {
    local pipeline_name="$1"
    local log_file="$2"

    if [[ ! -f "$log_file" ]]; then
        main_log "Warning: log file not found for ${pipeline_name}: ${log_file}"
        return 0
    fi

    {
        printf '\n'
        printf '==================== %s log begin ====================\n' "$pipeline_name"
        cat "$log_file"
        printf '==================== %s log end ====================\n' "$pipeline_name"
        printf '\n'
    } >> "$LOGFILE"
}

remove_running_pid() {
    local target_pid="$1"
    local -a remaining_pids=()
    local pid

    for pid in "${RUNNING_PIDS[@]}"; do
        if [[ "$pid" != "$target_pid" ]]; then
            remaining_pids+=("$pid")
        fi
    done

    RUNNING_PIDS=("${remaining_pids[@]}")
}

terminate_running_jobs() {
    local reason="$1"
    local pid pipeline_name

    if [[ ${#RUNNING_PIDS[@]} -eq 0 ]]; then
        return 0
    fi

    main_log "Terminating remaining pipeline jobs: ${reason}"
    for pid in "${RUNNING_PIDS[@]}"; do
        pipeline_name="${PID_TO_NAME[$pid]:-unknown}"
        main_log "Sending SIGTERM to ${pipeline_name} (pid=${pid})"
        # Try process-group kill first (negative pid), then fallback to direct pid.
        kill -- "-${pid}" 2>/dev/null || kill "$pid" 2>/dev/null || true
    done

    if (( PIPELINE_TERMINATION_GRACE_SECONDS > 0 )); then
        sleep "$PIPELINE_TERMINATION_GRACE_SECONDS" || true
    fi

    for pid in "${RUNNING_PIDS[@]}"; do
        pipeline_name="${PID_TO_NAME[$pid]:-unknown}"
        main_log "Sending SIGKILL to ${pipeline_name} (pid=${pid})"
        kill -- "-${pid}" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    done
}

start_pipeline_job() {
    local pipeline_name="$1"
    local timeout_seconds="$2"
    local script="$3"
    local log_file="$4"
    local -a command=()
    local command_line

    build_pipeline_command "$script" command
    command_line="$(build_cmdline_string "${command[@]}")"

    main_log "Launching ${pipeline_name} (timeout=${timeout_seconds}s, log=${log_file})"
    run_pipeline_detached "$timeout_seconds" "$command_line"

    local pid=$!
    PID_TO_NAME["$pid"]="$pipeline_name"
    PID_TO_LOGFILE["$pid"]="$log_file"
    RUNNING_PIDS+=("$pid")
    main_log "Started ${pipeline_name} (pid=${pid})"
}

wait_for_parallel_jobs() {
    local completed_pid=""
    local exit_code=0
    local pipeline_name log_file

    while (( ${#RUNNING_PIDS[@]} > 0 )); do
        # Wait until any background job exits. `wait -n` is portable on modern bash,
        # but not all shells support returning the pid (-p). To remain portable,
        # use `wait -n` to reap one child and then determine which PID exited by
        # probing RUNNING_PIDS with `kill -0`.
        wait -n
        exit_code=$?

        # Identify which PID has exited by checking which previously-running PID
        # no longer responds to kill -0. If multiple exited simultaneously, pick
        # the first one we detect.
        completed_pid=""
        for pid in "${RUNNING_PIDS[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                completed_pid="$pid"
                break
            fi
        done

        # As a fallback (very unlikely), if we couldn't detect which pid exited,
        # choose the first tracked PID so we can continue cleanup logic without
        # producing a bad array subscript.
        if [[ -z "$completed_pid" ]]; then
            completed_pid="${RUNNING_PIDS[0]}"
        fi

        pipeline_name="${PID_TO_NAME[$completed_pid]:-unknown}"
        log_file="${PID_TO_LOGFILE[$completed_pid]:-}"
        main_log "${pipeline_name} (pid=${completed_pid}) finished with exit code ${exit_code}"
        append_pipeline_log_to_main "$pipeline_name" "$log_file"
        remove_running_pid "$completed_pid"

        if [[ $exit_code -ne 0 ]]; then
            # Fail fast: if either parallel pipeline fails, stop everything immediately.
            terminate_running_jobs "${pipeline_name} failed with exit code ${exit_code}"
            return "$exit_code"
        fi
    done

    return 0
}

run_single_pipeline() {
    local pipeline_name="$1"
    local timeout_seconds="$2"
    local script="$3"
    local log_file="$4"
    local -a command=()

    build_pipeline_command "$script" command
    main_log "Running ${pipeline_name}..."

    if run_pipeline_command "$timeout_seconds" "${command[@]}"; then
        main_log "${pipeline_name} completed successfully."
        append_pipeline_log_to_main "$pipeline_name" "$log_file"
        return 0
    else
        local exit_code=$?
        main_log "Error: ${pipeline_name} failed with exit code ${exit_code}."
        append_pipeline_log_to_main "$pipeline_name" "$log_file"
        return "$exit_code"
    fi
}

cleanup_main_log() {
    local exit_code=$?

    if [[ ${#RUNNING_PIDS[@]} -gt 0 ]]; then
        # Safety net for unexpected exits (ctrl-c, set -e abort, etc.).
        terminate_running_jobs "main.sh exiting with status ${exit_code}"
    fi

    if [[ $exit_code -eq 0 ]]; then
        log_pipeline_run_end "success"
    else
        log_pipeline_run_end "failure(exit_code=${exit_code})"
    fi
}

trap cleanup_main_log EXIT

main_log "========================================"
main_log "Master pipeline orchestration"
main_log "BIDS_ROOT: $BIDS_ROOT"
main_log "SUBJECT: $SUBJECT"
main_log "SESSION: ${SESSION:-all-sessions}"
main_log "Log: $LOGFILE"
main_log "COMMAND_LINE: $COMMAND_LINE"
main_log "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
main_log "========================================"
main_log "Parallel stage timeouts: func=${FUNC_PIPELINE_TIMEOUT_SECONDS}s anat=${ANAT_PIPELINE_TIMEOUT_SECONDS}s"
main_log "Sequential stage timeouts: coreg=${COREG_PIPELINE_TIMEOUT_SECONDS}s samsrf=${SAMSRF_PIPELINE_TIMEOUT_SECONDS}s"

FUNC_SCRIPT="$SCRIPT_DIR/func_pipeline.sh"
ANAT_SCRIPT="$SCRIPT_DIR/anat_pipeline.sh"
COREG_SCRIPT="$SCRIPT_DIR/coreg_pipeline.sh"
SAMSRF_SCRIPT="$SCRIPT_DIR/samsrf_pipeline.sh"

FUNC_LOGFILE="$(pipeline_log_path "func_pipeline")"
ANAT_LOGFILE="$(pipeline_log_path "anat_pipeline")"
COREG_LOGFILE="$(pipeline_log_path "coreg_pipeline")"
SAMSRF_LOGFILE="$(pipeline_log_path "samsrf_pipeline")"

main_log "Launching func and anat pipelines in parallel..."
# Stage 1: independent pipelines, started together to save wall-clock time.
start_pipeline_job "func_pipeline" "$FUNC_PIPELINE_TIMEOUT_SECONDS" "$FUNC_SCRIPT" "$FUNC_LOGFILE"
start_pipeline_job "anat_pipeline" "$ANAT_PIPELINE_TIMEOUT_SECONDS" "$ANAT_SCRIPT" "$ANAT_LOGFILE"

main_log "Waiting for func and anat to finish..."
wait_for_parallel_jobs

# Stage 2 and 3 are sequential because they depend on prior outputs.
run_single_pipeline "coreg_pipeline" "$COREG_PIPELINE_TIMEOUT_SECONDS" "$COREG_SCRIPT" "$COREG_LOGFILE"
run_single_pipeline "samsrf_pipeline" "$SAMSRF_PIPELINE_TIMEOUT_SECONDS" "$SAMSRF_SCRIPT" "$SAMSRF_LOGFILE"

main_log "All pipelines completed successfully."
exit 0