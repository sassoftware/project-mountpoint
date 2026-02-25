#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Enhanced Compute Engine (ECE) Cache File Analyzer
# Analyzes SAS Compute Server pods for pre-deleted files with open handles in /tmp
# Provides full, simple, or concise reporting modes

NAMESPACE="${1:-viya-vol}"
MODE="${2:-full}"

# Validate mode
if [[ ! "$MODE" =~ ^(full|simple|concise)$ ]]; then
    echo "Error: Invalid mode '$MODE'. Use: full, simple, or concise"
    echo "Usage: $0 [namespace] [full|simple|concise]"
    exit 1
fi

# Find SAS Compute Server pods
COMPUTE_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep "sas-compute-server" | awk '{print $1}')
if [ -z "$COMPUTE_PODS" ]; then
    echo "Error: No SAS Compute Server pods found in namespace $NAMESPACE"
    exit 1
fi

# Get the newest compute pod (similar to find-sas-compute.sh logic)
TARGET_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers --sort-by=.metadata.creationTimestamp | grep sas-compute-server | tail -1 | awk '{print $1}')

if [ -z "$TARGET_POD" ]; then
    echo "Error: Could not determine target SAS Compute Server pod"
    exit 1
fi

# Mode-specific output
case "$MODE" in
    "full")
        echo "Analyzing Enhanced Compute Engine (ECE) cache files in namespace: $NAMESPACE (mode: $MODE)"
        echo "================================================================================"
        echo -e "Found SAS Compute Server pod(s):\n$COMPUTE_PODS"
        echo ""
        echo "Target pod: $TARGET_POD (Enhanced Compute Engine)"
        echo ""
        ;;
    "simple")
        echo "Analyzing pod: $TARGET_POD (Enhanced Compute Engine)"
        echo ""
        ;;
    "concise")
        echo "Analyzing pod: $TARGET_POD (Enhanced Compute Engine)"
        echo ""
        ;;
esac

# Get SAS processes (look for compsrv processes within the pod)
SAS_PIDS=$(kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-programming-environment -- ps aux | grep "compsrv" | grep -v grep | awk '{print $2}')
if [ -z "$SAS_PIDS" ]; then
    echo "Error: No SAS compute processes found in pod $TARGET_POD"
    exit 1
fi

[[ "$MODE" == "full" ]] && echo "Found SAS processes: $(echo $SAS_PIDS | tr '\n' ' ')" && echo ""

if [[ "$MODE" == "concise" ]]; then
    # Concise mode: Group files by owning PID
    declare -A PID_FILES
    declare -A PID_SIZES  
    declare -A PID_COUNTS
    
    for PID in $SAS_PIDS; do
        # Look for deleted files in /tmp mount path specifically
        FILES=$(kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-programming-environment -- ls -la /proc/$PID/fd 2>/dev/null | grep "deleted" | grep "/tmp" || true)
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            FILE_PATH=$(echo "$line" | sed -n 's/.*-> \(.*\) (deleted).*/\1/p')
            [[ -z "$FILE_PATH" ]] && continue
            
            # Only process files in /tmp path
            if [[ "$FILE_PATH" == *"/tmp/"* ]]; then
                FILENAME=$(basename "$FILE_PATH")
                SIZE_BYTES=$(echo "$FILENAME" | grep -o '[0-9]*$')
                
                if [[ -n "$SIZE_BYTES" ]] && [[ "$SIZE_BYTES" -gt 0 ]] 2>/dev/null; then
                    PID_FILES[$PID]="${PID_FILES[$PID]} $FILE_PATH"
                    PID_SIZES[$PID]="${PID_SIZES[$PID]} $SIZE_BYTES" 
                    PID_COUNTS[$PID]=$((${PID_COUNTS[$PID]:-0} + 1))
                fi
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
        kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-programming-environment -- ps -p "$PID" >/dev/null 2>&1 && TYPE="ACTIVE"
        
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
    
    for PID in $SAS_PIDS; do
        # Look for deleted files in /tmp mount path specifically
        DELETED_FILES=$(kubectl exec -n "$NAMESPACE" "$TARGET_POD" -c sas-programming-environment -- ls -la /proc/$PID/fd 2>/dev/null | grep "deleted" | grep "/tmp" || true)
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            FILE_PATH=$(echo "$line" | sed -n 's/.*-> \(.*\) (deleted).*/\1/p')
            [[ -z "$FILE_PATH" ]] && continue
            
            # Only process files in /tmp path
            if [[ "$FILE_PATH" == *"/tmp/"* ]]; then
                FILENAME=$(basename "$FILE_PATH")
                DIRECTORY=$(dirname "$FILE_PATH")
                SIZE_BYTES=$(echo "$FILENAME" | grep -o '[0-9]*$')
                
                if [[ -n "$SIZE_BYTES" ]] && [[ "$SIZE_BYTES" -gt 0 ]] 2>/dev/null; then
                    SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $SIZE_BYTES / 1024 / 1024}")
                    TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))
                    FILE_COUNT=$((FILE_COUNT + 1))
                    
                    printf "%-60s %-25s %-15s\n" "$FILENAME" "$DIRECTORY" "$SIZE_MB"
                fi
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
        echo "PIDs with ECE cache: $PID_COUNT"
        echo "Total ECE cache size: ${TOTAL_MB} MB (${TOTAL_GB} GB)"
        echo ""
    else
        echo "No ECE cache files found."
    fi
elif [[ "$FILE_COUNT" -gt 0 ]]; then
    TOTAL_MB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE / 1024 / 1024}")
    TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE / 1024 / 1024 / 1024}")
    
    if [[ "$MODE" == "full" ]]; then
        echo "Summary:"
        echo "--------"
        echo "Total ECE cache files: $FILE_COUNT"
        echo "Total size: ${TOTAL_MB} MB (${TOTAL_GB} GB)"
        echo ""
    fi
else
    echo "No ECE cache files found in any SAS Compute Server processes."
fi