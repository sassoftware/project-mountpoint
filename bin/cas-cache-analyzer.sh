#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# CAS Cache File Analyzer
# Provides full, simple, or concise reporting modes

NAMESPACE="${1:-viya-vol}"
MODE="${2:-full}"

# Validate mode
if [[ ! "$MODE" =~ ^(full|simple|concise)$ ]]; then
    echo "Error: Invalid mode '$MODE'. Use: full, simple, or concise"
    echo "Usage: $0 [namespace] [full|simple|concise]"
    exit 1
fi

# Find CAS pods
CAS_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep "sas-cas-server-default" | awk '{print $1}')
if [ -z "$CAS_PODS" ]; then
    echo "Error: No default CAS server pods found in namespace $NAMESPACE"
    exit 1
fi

# Determine target pod
CONTROLLER_POD=$(echo "$CAS_PODS" | grep "controller" | head -1)
WORKER_POD=$(echo "$CAS_PODS" | grep "worker" | head -1)
TARGET_POD=${WORKER_POD:-$CONTROLLER_POD}
DEPLOYMENT_TYPE="SMP"
[ -n "$WORKER_POD" ] && DEPLOYMENT_TYPE="MPP"

# Mode-specific output
case "$MODE" in
    "full")
        echo "Analyzing CAS cache files in namespace: $NAMESPACE (mode: $MODE)"
        echo "=================================================="
        echo "Found CAS pods: $CAS_PODS"
        echo ""
        echo "Target pod: $TARGET_POD ($DEPLOYMENT_TYPE)"
        echo ""
        ;;
    "simple")
        echo "Analyzing pod: $TARGET_POD ($DEPLOYMENT_TYPE)"
        echo ""
        ;;
    "concise")
        echo "Analyzing pod: $TARGET_POD ($DEPLOYMENT_TYPE)"
        echo ""
        ;;
esac

# Get CAS processes
CAS_PIDS=$(kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-cas-server -- ps aux | grep "bin/cas " | grep -v grep | awk '{print $2}')
if [ -z "$CAS_PIDS" ]; then
    echo "Error: No CAS processes found in pod $TARGET_POD"
    exit 1
fi

[[ "$MODE" == "full" ]] && echo "Found CAS processes: $(echo $CAS_PIDS | tr '\n' ' ')" && echo ""

if [[ "$MODE" == "concise" ]]; then
    # Concise mode: Group files by owning PID
    declare -A PID_FILES
    declare -A PID_SIZES  
    declare -A PID_COUNTS
    
    for PID in $CAS_PIDS; do
        FILES=$(kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-cas-server -- ls -la /proc/$PID/fd 2>/dev/null | grep "deleted" || true)
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            FILE_PATH=$(echo "$line" | sed -n 's/.*-> \(.*\) (deleted).*/\1/p')
            [[ -z "$FILE_PATH" ]] && continue
            
            FILENAME=$(basename "$FILE_PATH")
            SIZE_BYTES=$(echo "$FILENAME" | grep -o '[0-9]*$')
            
            if [[ -n "$SIZE_BYTES" ]] && [[ "$SIZE_BYTES" -gt 0 ]] 2>/dev/null; then
                PID_FILES[$PID]="${PID_FILES[$PID]} $FILE_PATH"
                PID_SIZES[$PID]="${PID_SIZES[$PID]} $SIZE_BYTES" 
                PID_COUNTS[$PID]=$((${PID_COUNTS[$PID]:-0} + 1))
            fi
        done <<< "$FILES"
    done
    
    # Display header
    printf "%-15s %-25s %-15s %-10s %-10s\n" "PID OWNER" "DIRECTORY" "SIZE (MB)" "CHUNKS" "TYPE"
    echo "=============== ========================= =============== ========== =========="
    
    TOTAL_SIZE=0
    PID_COUNT=0
    
    # Display one entry per PID with cache files
    for PID in "${!PID_FILES[@]}"; do
        COUNT=${PID_COUNTS[$PID]}
        SIZES_ARRAY=(${PID_SIZES[$PID]})
        FILES_ARRAY=(${PID_FILES[$PID]})
        
        # Calculate total size for this PID's files
        PID_TOTAL_SIZE=0
        for size in "${SIZES_ARRAY[@]}"; do
            PID_TOTAL_SIZE=$((PID_TOTAL_SIZE + size))
        done
        
        # Get representative info from first file
        FIRST_FILE=${FILES_ARRAY[0]}
        DIRECTORY=$(dirname "$FIRST_FILE")
        SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $PID_TOTAL_SIZE / 1024 / 1024}")
        
        # Check if process is running
        TYPE="LEGACY"
        kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-cas-server -- ps -p "$PID" >/dev/null 2>&1 && TYPE="ACTIVE"
        
        printf "%-15s %-25s %-15s %-10s %-10s\n" "$PID" "$DIRECTORY" "$SIZE_MB" "$COUNT" "$TYPE"
        
        TOTAL_SIZE=$((TOTAL_SIZE + PID_TOTAL_SIZE))
        PID_COUNT=$((PID_COUNT + 1))
    done
else
    # Full and Simple modes: show all individual files
    printf "%-60s %-25s %-15s\n" "CACHE FILE" "DIRECTORY" "SIZE (MB)"
    echo "============================================================ ========================= ==============="
    
    TOTAL_SIZE=0
    FILE_COUNT=0
    
    for PID in $CAS_PIDS; do
        DELETED_FILES=$(kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-cas-server -- ls -la /proc/$PID/fd 2>/dev/null | grep "deleted" || true)
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            FILE_PATH=$(echo "$line" | sed -n 's/.*-> \(.*\) (deleted).*/\1/p')
            [[ -z "$FILE_PATH" ]] && continue
            
            FILENAME=$(basename "$FILE_PATH")
            DIRECTORY=$(dirname "$FILE_PATH")
            SIZE_BYTES=$(echo "$FILENAME" | grep -o '[0-9]*$')
            
            if [[ -n "$SIZE_BYTES" ]] && [[ "$SIZE_BYTES" -gt 0 ]] 2>/dev/null; then
                SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $SIZE_BYTES / 1024 / 1024}")
                TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))
                FILE_COUNT=$((FILE_COUNT + 1))
                
                printf "%-60s %-25s %-15s\n" "$FILENAME" "$DIRECTORY" "$SIZE_MB"
            fi
        done <<< "$DELETED_FILES"
    done
fi

# Display summary
echo ""
if [[ "$MODE" == "concise" ]]; then
    if [[ "$PID_COUNT" -gt 0 ]]; then
        TOTAL_MB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE / 1024 / 1024}")
        TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE / 1024 / 1024 / 1024}")
        
        echo "Summary (grouped by PID owner):"
        echo "--------------------------------"
        echo "PIDs with cache: $PID_COUNT"
        echo "Total cache size: ${TOTAL_MB} MB (${TOTAL_GB} GB)"
        echo ""
    else
        echo "No cache files found."
    fi
elif [[ "$FILE_COUNT" -gt 0 ]]; then
    TOTAL_MB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE / 1024 / 1024}")
    TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE / 1024 / 1024 / 1024}")
    
    if [[ "$MODE" == "full" ]]; then
        echo "Summary:"
        echo "--------"
        echo "Total cache files: $FILE_COUNT"
        echo "Total size: ${TOTAL_MB} MB (${TOTAL_GB} GB)"
        echo ""
    fi
else
    echo "No cache files found in any CAS processes."
fi