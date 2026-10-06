#!/bin/bash

set -e

LOG_FILE="./results/perf_logs/synth_runs.log"

CONFIGS=(
    "-c ingress_top -dp N_STREAMS 1 -msg n1_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 5 -msg n5_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 10 -msg n10_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 15 -msg n15_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 20 -msg n20_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 25 -msg n25_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 50 -msg n50_m64_md_1024"
    "-c ingress_top -dp N_STREAMS 100 -msg n100_m64_md_1024"
)

TOTAL=${#CONFIGS[@]}
echo "=== Start $TOTAL syntheses: $(date) ===" | tee -a "$LOG_FILE"

RUN=1
for ARGS in "${CONFIGS[@]}"; do
    echo "--------------------------------------------------" | tee -a "$LOG_FILE"
    echo "[$(date +'%H:%M:%S')] Run $RUN/$TOTAL" | tee -a "$LOG_FILE"
    echo "  Args: $ARGS" | tee -a "$LOG_FILE"
    
    START_TIME=$SECONDS
    
    teda risc-v-streaming synthesis $ARGS
    
    DURATION=$((SECONDS - START_TIME))
    echo "[$(date +'%H:%M:%S')] Run $RUN/$TOTAL successfully done (Duration: $((DURATION / 60))m $((DURATION % 60))s)." | tee -a "$LOG_FILE"
    
    ((RUN++))
done

echo "==================================================" | tee -a "$LOG_FILE"
echo "All $TOTAL syntheses completed: $(date)" | tee -a "$LOG_FILE"
