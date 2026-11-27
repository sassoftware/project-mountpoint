#!/usr/bin/env bash
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# parse_localpath_timing.sh
# Fetch the full Rancher local-path provisioner log and emit a simple table of
# provisioning durations for PVCs whose names end in -viya or -tmp.
# Usage: parse_localpath_timing.sh [-r|--reverse]

SORT_DIR=""
if [ "$1" == "-r" ] || [ "$1" == "--reverse" ]; then
  SORT_DIR="-r"
fi

LOG=$(kubectl logs -n local-path-storage deployment/local-path-provisioner --timestamps=true 2>/dev/null)
if [ -z "$LOG" ]; then
  echo "No logs retrieved from local-path provisioner" >&2
  exit 1
fi

declare -A started
declare -A created

# Parse "Creating volume ..." start lines.
while IFS= read -r line; do
  ts=$(echo "$line" | awk '{print $1}')
  ts=${ts%Z}
  # PVC name is the tail of the path after "_viya_" (stops before a quote or whitespace)
  pvc=$(echo "$line" | grep -oE '_viya_[^"[:space:]]+' | tail -1 | sed 's/_viya_//')
  if [[ -n "$pvc" && "$pvc" =~ -viya$|-tmp$ ]]; then
    started[$pvc]=$ts
  fi
done <<< "$(printf '%s\n' "$LOG" | grep 'Creating volume')"

# Parse "Volume ... has been created" completion lines.
while IFS= read -r line; do
  ts=$(echo "$line" | awk '{print $1}')
  ts=${ts%Z}
  pvc=$(echo "$line" | grep -oE '_viya_[^"[:space:]]+' | tail -1 | sed 's/_viya_//')
  if [[ -n "$pvc" && "$pvc" =~ -viya$|-tmp$ ]]; then
    created[$pvc]=$ts
  fi
done <<< "$(printf '%s\n' "$LOG" | grep 'has been created')"

BODY_FILE=$(mktemp /tmp/parse_localpath_body.XXXXXX)

for pvc in "${!started[@]}"; do
  s=${started[$pvc]}
  e=${created[$pvc]}
  if [ -n "$e" ]; then
    start_epoch=$(date -d "$s" +%s.%N 2>/dev/null)
    end_epoch=$(date -d "$e" +%s.%N 2>/dev/null)
    elapsed=$(awk -v s="$start_epoch" -v e="$end_epoch" 'BEGIN{printf "%.3f", e-s}')
    completed=${e##*T}
  else
    elapsed="N/A"
    completed="N/A"
  fi
  printf "%s|%ss|%s|%s\n" "$pvc" "$elapsed" "$s" "$completed" >> "$BODY_FILE"
done

{ printf "%s|%s|%s|%s\n" "PVC" "Elapsed" "Started" "Completed"
  sort -t'|' -k3,3 ${SORT_DIR} "$BODY_FILE"
} | column -t -s '|'

rm -f "$BODY_FILE"