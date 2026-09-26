#!/bin/bash

set -e

LOG_FILE="./results/perf_logs/simulation_runs.log"

CONFIGS=(
    "-c rtl -tp MODULE top -dp B_BANKS 8 -dp W_WORKERS 7"
    "-c rtl -tp MODULE top -dp B_BANKS 8 -dp W_WORKERS 6"
    "-c rtl -tp MODULE top -dp B_BANKS 8 -dp W_WORKERS 5"
    "-c rtl -tp MODULE top -dp B_BANKS 8 -dp W_WORKERS 4"
    "-c rtl -tp MODULE top -dp B_BANKS 4 -dp W_WORKERS 3"
    "-c rtl -tp MODULE top -dp B_BANKS 4 -dp W_WORKERS 2"
    "-c rtl -tp MODULE top -dp B_BANKS 2 -dp W_WORKERS 1"
    "-c rtl -tp MODULE top -dp B_BANKS 1 -dp W_WORKERS 1"
)

TOTAL=${#CONFIGS[@]}
echo "=== Start $TOTAL simulations: $(date) ===" | tee -a "$LOG_FILE"

RUN=1
for ARGS in "${CONFIGS[@]}"; do
    echo "--------------------------------------------------" | tee -a "$LOG_FILE"
    echo "[$(date +'%H:%M:%S')] Run $RUN/$TOTAL" | tee -a "$LOG_FILE"
    echo "  Args: $ARGS" | tee -a "$LOG_FILE"
    
    START_TIME=$SECONDS
    
    teda risc-v-streaming simulation $ARGS
    
    DURATION=$((SECONDS - START_TIME))
    echo "[$(date +'%H:%M:%S')] Run $RUN/$TOTAL successfully done (Duration: $((DURATION / 60))m $((DURATION % 60))s)." | tee -a "$LOG_FILE"
    
    ((RUN++))
done

echo "==================================================" | tee -a "$LOG_FILE"
echo "All $TOTAL simulations completed: $(date)" | tee -a "$LOG_FILE"
