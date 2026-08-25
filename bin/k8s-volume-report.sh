#!/usr/bin/env bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# k8s-volume-report.sh
# Report Kubernetes pod volumes by namespace, pod name/pattern, or storage type.
#
# Dependencies: kubectl, jq

set -uo pipefail

NAMESPACE=""
POD_PATTERN=""
VOL_TYPE=""
CLAIM_NAME=""
STORAGE_ONLY=false

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage:
  k8s-volume-report.sh -n NAMESPACE
      Namespace-wide count summary by volume type

  k8s-volume-report.sh -n NAMESPACE -p POD_NAME
      Full volume detail table for a single pod (all volume types shown)

  k8s-volume-report.sh -n NAMESPACE -p 'GLOB*'
      Per-pod storage highlights for matching pods:
        emptyDir count + hostPath / PVC / GeV detail table
      Quote the glob pattern to prevent shell expansion.

  k8s-volume-report.sh -n NAMESPACE -t TYPE [-p GLOB]
      Flat table of every volume of TYPE across all pods (optionally filtered).
      TYPE may be: PVC, GeV, hostPath, emptyDir, configMap, secret, projected, downwardAPI
      Columns are tailored to the type (access mode, storageClass, size, etc.)

  k8s-volume-report.sh -n NAMESPACE -c CLAIM_NAME
      PVC report: claim stats, CSI physical location, and pods using it.
      Running pods are listed first; completed/failed pods follow.

Options:
  -n  Kubernetes namespace (required)
  -p  Pod name or glob pattern (optional; filters all modes)
  -t  Volume type to search for (enables type-report mode)
  -c  PVC claim name (enables PVC report mode)
  -s  Storage-only: in glob mode, suppress pods with no PVC/GeV/hostPath volumes
  -h  Show this help
EOF
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# ─── Parse arguments ──────────────────────────────────────────────────────────
while getopts ":n:p:t:c:sh" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    p) POD_PATTERN="$OPTARG" ;;
    t) VOL_TYPE="$OPTARG" ;;
    c) CLAIM_NAME="$OPTARG" ;;
    s) STORAGE_ONLY=true ;;
    h) usage 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
   \?) die "Unknown option: -$OPTARG" ;;
  esac
done

[[ -z "$NAMESPACE" ]] && { echo "Namespace (-n) is required." >&2; usage 1; }
command -v kubectl &>/dev/null || die "kubectl not found in PATH"
command -v jq     &>/dev/null || die "jq not found in PATH"

# ─── Fetch cluster data ───────────────────────────────────────────────────────
echo "Fetching data from namespace '${NAMESPACE}'..." >&2
PODS_JSON=$(kubectl get pods -n "$NAMESPACE" -o json) || die "kubectl get pods failed"
PVCS_JSON=$(kubectl get pvc  -n "$NAMESPACE" -o json) || die "kubectl get pvc failed"

# Build PVC info lookup: { "claim-name": { accessModes, storageClass, size } }
PVC_MAP=$(jq '
  .items | map({
    key: .metadata.name,
    value: {
      accessModes:  (.spec.accessModes | map(
                      if   . == "ReadWriteMany"    then "RWX"
                      elif . == "ReadWriteOnce"    then "RWO"
                      elif . == "ReadOnlyMany"     then "ROX"
                      elif . == "ReadWriteOncePod" then "RWOP"
                      else . end) | join("/")),
      storageClass: (.spec.storageClassName // "-"),
      size:         (.status.capacity.storage // .spec.resources.requests.storage // "?")
    }
  }) | from_entries
' <<< "$PVCS_JSON")

# ─── Formatting helpers ───────────────────────────────────────────────────────
hr() {
  local n="${1:-140}" i
  for ((i = 0; i < n; i++)); do printf '─'; done
  printf '\n'
}

trunc() {
  local s="$1" n="$2"
  if (( ${#s} > n )); then printf '%s…' "${s:0:$((n-1))}"; else printf '%s' "$s"; fi
}

# ─── JQ filter: classify every volume (all types) — TSV output ───────────────
# Columns: name, type, claim/path, access, storageClass, size, medium
# Sorted: PVC → GeV → hostPath → emptyDir → configMap → secret → projected → other
JQ_ALL='
  [ .spec.volumes[]? |
    (
      if   .emptyDir             then { t:"emptyDir",
                                        c:"-", a:"-", s:"-",
                                        z:(.emptyDir.sizeLimit // "unlimited"),
                                        m:(.emptyDir.medium    // "-") }
      elif .hostPath             then { t:"hostPath",
                                        c:.hostPath.path,
                                        a:"-", s:"-", z:"-",
                                        m:(.hostPath.type // "unset") }
      elif .persistentVolumeClaim then
        ( ($pm[.persistentVolumeClaim.claimName] //
             {accessModes:"-",storageClass:"-",size:"?"}) as $p |
          { t:"PVC", c:.persistentVolumeClaim.claimName,
            a:$p.accessModes, s:$p.storageClass, z:$p.size, m:"-" } )
      elif .ephemeral            then
        ( .ephemeral.volumeClaimTemplate.spec as $spec |
          ($pm[($pod + "-" + .name)] // {
            accessModes: ($spec.accessModes | map(
                           if   . == "ReadWriteMany"    then "RWX"
                           elif . == "ReadWriteOnce"    then "RWO"
                           elif . == "ReadOnlyMany"     then "ROX"
                           elif . == "ReadWriteOncePod" then "RWOP"
                           else . end) | join("/")),
            storageClass:($spec.storageClassName // "-"),
            size:        ($spec.resources.requests.storage // "?")
          }) as $i |
          { t:"GeV", c:"-",
            a:$i.accessModes, s:$i.storageClass, z:$i.size, m:"-" } )
      elif .configMap            then { t:"configMap",  c:(.configMap.name    // "-"), a:"-", s:"-", z:"-", m:"-" }
      elif .secret               then { t:"secret",     c:(.secret.secretName // "-"), a:"-", s:"-", z:"-", m:"-" }
      elif .projected            then { t:"projected",  c:"-", a:"-", s:"-", z:"-", m:"-" }
      elif .downwardAPI          then { t:"downwardAPI",c:"-", a:"-", s:"-", z:"-", m:"-" }
      else                            { t:"other",      c:"-", a:"-", s:"-", z:"-", m:"-" }
      end
    ) as $v |
    { pri: (if   $v.t == "PVC"         then 0
            elif $v.t == "GeV"         then 1
            elif $v.t == "hostPath"    then 2
            elif $v.t == "emptyDir"    then 3
            elif $v.t == "configMap"   then 4
            elif $v.t == "secret"      then 5
            elif $v.t == "projected"   then 6
            elif $v.t == "downwardAPI" then 7
            else 8 end),
      row: [ .name, $v.t, $v.c, $v.a, $v.s, $v.z, $v.m ] }
  ] | sort_by(.pri) | .[].row | @tsv
'

# ─── JQ filter: classify storage volumes only (hostPath, PVC, GeV) ───────────
# Columns: name, type, claim/path, access, storageClass, size
# Sorted: PVC → GeV → hostPath
JQ_STORAGE='
  [ .spec.volumes[]? |
    select(.hostPath or .persistentVolumeClaim or .ephemeral) |
    (
      if   .hostPath              then { t:"hostPath",
                                         c:.hostPath.path,
                                         a:"-", s:"-", z:"-" }
      elif .persistentVolumeClaim then
        ( ($pm[.persistentVolumeClaim.claimName] //
             {accessModes:"-",storageClass:"-",size:"?"}) as $p |
          { t:"PVC", c:.persistentVolumeClaim.claimName,
            a:$p.accessModes, s:$p.storageClass, z:$p.size } )
      elif .ephemeral             then
        ( .ephemeral.volumeClaimTemplate.spec as $spec |
          ($pm[($pod + "-" + .name)] // {
            accessModes: ($spec.accessModes | map(
                           if   . == "ReadWriteMany"    then "RWX"
                           elif . == "ReadWriteOnce"    then "RWO"
                           elif . == "ReadOnlyMany"     then "ROX"
                           elif . == "ReadWriteOncePod" then "RWOP"
                           else . end) | join("/")),
            storageClass:($spec.storageClassName // "-"),
            size:        ($spec.resources.requests.storage // "?")
          }) as $i |
          { t:"GeV", c:"-",
            a:$i.accessModes, s:$i.storageClass, z:$i.size } )
      else { t:"other", c:"-", a:"-", s:"-", z:"-" }
      end
    ) as $v |
    { pri: (if   $v.t == "PVC"      then 0
            elif $v.t == "GeV"      then 1
            elif $v.t == "hostPath" then 2
            else 3 end),
      row: [ .name, $v.t, $v.c, $v.a, $v.s, $v.z ] }
  ] | sort_by(.pri) | .[].row | @tsv
'

# ─── JQ filter: storage + emptyDir (PVC → GeV → hostPath → emptyDir) ────────────────
# Columns: name, type, claim/path, access, storageClass, size, medium
# Used by wildcard pod mode; emptyDir shows sizeLimit in SIZE and medium in MEDIUM
JQ_STORAGE_ALL='
  [ .spec.volumes[]? |
    select(.hostPath or .persistentVolumeClaim or .ephemeral or .emptyDir) |
    (
      if   .emptyDir              then { t:"emptyDir",
                                         c:"-", a:"-", s:"-",
                                         z:(.emptyDir.sizeLimit // "unlimited"),
                                         m:(.emptyDir.medium    // "-") }
      elif .hostPath              then { t:"hostPath",
                                         c:.hostPath.path,
                                         a:"-", s:"-", z:"-", m:"-" }
      elif .persistentVolumeClaim then
        ( ($pm[.persistentVolumeClaim.claimName] //
             {accessModes:"-",storageClass:"-",size:"?"}) as $p |
          { t:"PVC", c:.persistentVolumeClaim.claimName,
            a:$p.accessModes, s:$p.storageClass, z:$p.size, m:"-" } )
      elif .ephemeral             then
        ( .ephemeral.volumeClaimTemplate.spec as $spec |
          ($pm[($pod + "-" + .name)] // {
            accessModes: ($spec.accessModes | map(
                           if   . == "ReadWriteMany"    then "RWX"
                           elif . == "ReadWriteOnce"    then "RWO"
                           elif . == "ReadOnlyMany"     then "ROX"
                           elif . == "ReadWriteOncePod" then "RWOP"
                           else . end) | join("/")),
            storageClass:($spec.storageClassName // "-"),
            size:        ($spec.resources.requests.storage // "?")
          }) as $i |
          { t:"GeV", c:"-", a:$i.accessModes, s:$i.storageClass, z:$i.size, m:"-" } )
      else { t:"other", c:"-", a:"-", s:"-", z:"-", m:"-" }
      end
    ) as $v |
    { pri: (if   $v.t == "PVC"      then 0
            elif $v.t == "GeV"      then 1
            elif $v.t == "hostPath" then 2
            elif $v.t == "emptyDir" then 3
            else 4 end),
      row: [ .name, $v.t, $v.c, $v.a, $v.s, $v.z, $v.m ] }
  ] | sort_by(.pri) | .[].row | @tsv
'

# ─── MODE 1: Single pod — full detail (all volume types) ─────────────────────
#   VOLUME NAME(38)  TYPE(10)  CLAIM/PATH(51)  ACCESS(8)  STORAGECLASS(18)  SIZE(11)  MEDIUM(8)
#   Total width: 156
print_pod_detail() {
  local pod_name="$1" pod_json="$2"
  local W=156
  echo ""
  printf "Pod: %s\n" "$pod_name"
  hr $W
  printf "%-38s  %-10s  %-51s  %-8s  %-18s  %-11s  %-8s\n" \
    "VOLUME NAME" "TYPE" "CLAIM / PATH" "ACCESS" "STORAGECLASS" "SIZE" "MEDIUM"
  hr $W
  jq -r --argjson pm "$PVC_MAP" --arg pod "$pod_name" "$JQ_ALL" <<< "$pod_json" \
  | while IFS=$'\t' read -r vname vtype vclaim vaccess vsc vsize vmedium; do
      printf "%-38s  %-10s  %-51s  %-8s  %-18s  %-11s  %-8s\n" \
        "$(trunc "$vname"  38)" "$vtype" \
        "$(trunc "$vclaim" 51)" "$vaccess" \
        "$(trunc "$vsc"   18)" "$vsize" "$vmedium"
    done
  echo ""
}

# ─── MODE 2 (wildcard): Per-pod storage table ─────────────────────────────────
#   Table: PVC → GeV → hostPath → emptyDir (all storage-relevant volume types)
#   VOLUME NAME(36)  TYPE(10)  CLAIM/PATH(44)  ACCESS(8)  SC(18)  SIZE(11)  MEDIUM(8)
#   Total width (with 2-space indent): 149
#   -s flag suppresses pods that have no PVC/GeV/hostPath (emptyDir-only pods)
print_pod_storage() {
  local pod_name="$1" pod_json="$2"
  local W=149

  # Compute PVC/GeV/hostPath count (for -s) and total storage count (incl. emptyDir)
  local counts
  counts=$(jq -r '
    (.spec.volumes // []) |
    [ (map(select(.hostPath or .persistentVolumeClaim or .ephemeral))              | length),
      (map(select(.hostPath or .persistentVolumeClaim or .ephemeral or .emptyDir)) | length) ] |
    join(" ")
  ' <<< "$pod_json")
  local storage_count total_count
  read -r storage_count total_count <<< "$counts"

  # In -s mode, skip pods with no PVC/GeV/hostPath entirely
  if [[ "$STORAGE_ONLY" == true ]] && (( storage_count == 0 )); then
    return
  fi

  echo ""
  printf "Pod: %s\n" "$pod_name"

  if (( total_count == 0 )); then
    printf "  (no storage volumes)\n"
    return
  fi

  hr $W
  printf "  %-36s  %-10s  %-44s  %-8s  %-18s  %-11s  %-8s\n" \
    "VOLUME NAME" "TYPE" "CLAIM / PATH" "ACCESS" "STORAGECLASS" "SIZE" "MEDIUM"
  hr $W
  jq -r --argjson pm "$PVC_MAP" --arg pod "$pod_name" "$JQ_STORAGE_ALL" <<< "$pod_json" \
  | while IFS=$'\t' read -r vname vtype vclaim vaccess vsc vsize vmedium; do
      printf "  %-36s  %-10s  %-44s  %-8s  %-18s  %-11s  %-8s\n" \
        "$(trunc "$vname"  36)" "$vtype" \
        "$(trunc "$vclaim" 44)" "$vaccess" \
        "$(trunc "$vsc"   18)" "$vsize" "$vmedium"
    done
}

# ─── MODE 3: Namespace-wide summary ──────────────────────────────────────────
print_namespace_summary() {
  # Use mapfile + per-line jq output to avoid bash IFS=$'\t' collapsing empty fields.
  local -a _v
  mapfile -t _v < <(jq -r --argjson pm "$PVC_MAP" '
    .items as $pods |
    [
      ($pods | length),

      ($pods | map(.spec.volumes // [] | map(select(.emptyDir))                                  | length) | add // 0),
      ($pods | map(select((.spec.volumes // []) | map(select(.emptyDir))                         | length > 0)) | length),
      ($pods | map(.spec.volumes // [] | map(select(.emptyDir and .emptyDir.sizeLimit))          | length) | add // 0),
      ($pods | map(.spec.volumes // [] | map(select(.emptyDir and .emptyDir.medium == "Memory")) | length) | add // 0),

      ($pods | map(.spec.volumes // [] | map(select(.hostPath)) | length) | add // 0),
      ($pods | map(select((.spec.volumes // []) | map(select(.hostPath)) | length > 0)) | length),
      ([$pods[] | .spec.volumes // [] | .[] | select(.hostPath) | .hostPath.path] | unique | join(", ")),

      ($pods | map(.spec.volumes // [] | map(select(.persistentVolumeClaim)) | length) | add // 0),
      ($pods | map(select((.spec.volumes // []) | map(select(.persistentVolumeClaim)) | length > 0)) | length),
      ([$pods[] | .spec.volumes // [] | .[] | select(.persistentVolumeClaim) | .persistentVolumeClaim.claimName] | unique | length),
      ([$pods[] | .spec.volumes // [] | .[] | select(.persistentVolumeClaim) | .persistentVolumeClaim.claimName | $pm[.].storageClass // "?"] | unique | sort | join(", ")),

      ($pods | map(.spec.volumes // [] | map(select(.ephemeral)) | length) | add // 0),
      ($pods | map(select((.spec.volumes // []) | map(select(.ephemeral)) | length > 0)) | length),
      ([$pods[] | .spec.volumes // [] | .[] | select(.ephemeral) |
         { sc:.ephemeral.volumeClaimTemplate.spec.storageClassName,
           sz:.ephemeral.volumeClaimTemplate.spec.resources.requests.storage }] |
       group_by(.sc) |
       map("\(.[0].sc): \([.[].sz] | group_by(.) | map("\(.[0])×\(length)") | join(", "))") |
       join("  |  "))
    ] | .[] | tostring
  ' <<< "$PODS_JSON")

  local pod_count="${_v[0]}"
  local ed_total="${_v[1]}" ed_pods="${_v[2]}" ed_limit="${_v[3]}" ed_mem="${_v[4]}"
  local hp_total="${_v[5]}" hp_pods="${_v[6]}" hp_paths="${_v[7]}"
  local pvc_total="${_v[8]}" pvc_pods="${_v[9]}" pvc_unique="${_v[10]}" pvc_scs="${_v[11]}"
  local gev_total="${_v[12]}" gev_pods="${_v[13]}" gev_detail="${_v[14]}"

  local W=105
  echo ""
  printf "Volume Summary — namespace: %s  (%s pods)\n" "$NAMESPACE" "$pod_count"
  hr $W
  printf "%-12s  %7s  %11s  %s\n" "TYPE" "COUNT" "PODS W/TYPE" "DETAILS"
  hr $W
  printf "%-12s  %7s  %11s  %s\n" "emptyDir" "$ed_total" "$ed_pods" \
    "${ed_limit} w/ sizeLimit  |  ${ed_mem} w/ Memory medium"
  printf "%-12s  %7s  %11s  %s\n" "hostPath" "$hp_total" "$hp_pods" \
    "${hp_paths:-(none)}"
  printf "%-12s  %7s  %11s  %s\n" "PVC"      "$pvc_total" "$pvc_pods" \
    "${pvc_unique} unique claims  |  StorageClasses: ${pvc_scs:-(none)}"
  printf "%-12s  %7s  %11s  %s\n" "GeV"      "$gev_total" "$gev_pods" \
    "${gev_detail:-(none)}"
  hr $W
  echo ""
}

# ─── MODE 4: Type report — flat table of every volume of a given type ──────────
# -t TYPE [-p GLOB]  Rows sorted by pod name → volume name.
# Pod name printed once per group; subsequent volumes in same pod show blank pod column.
# Valid types: PVC, GeV, hostPath, emptyDir, configMap, secret, projected, downwardAPI
print_type_report() {
  local vtype
  case "${VOL_TYPE,,}" in
    pvc|persistentvolumeclaim)             vtype="PVC"         ;;
    gev|ephemeral|genericephemeralvolume)  vtype="GeV"         ;;
    hostpath)                              vtype="hostPath"    ;;
    emptydir)                              vtype="emptyDir"    ;;
    configmap)                             vtype="configMap"   ;;
    secret)                                vtype="secret"      ;;
    projected)                             vtype="projected"   ;;
    downwardapi)                           vtype="downwardAPI" ;;
    *) die "Unknown type '${VOL_TYPE}'. Valid: PVC, GeV, hostPath, emptyDir, configMap, secret, projected, downwardAPI" ;;
  esac

  local filter_note=""
  [[ -n "$POD_PATTERN" ]] && filter_note="  (pods: '${POD_PATTERN}')"
  echo ""
  printf "Type Report — %s  namespace: %s%s\n" "$vtype" "$NAMESPACE" "$filter_note"

  local W=0 matched=0 last_pod=""

  case "$vtype" in

    # ── PVC: POD(48) VOL(34) CLAIM(44) ACCESS(8) SC(18) SIZE(11) = 173 ──────
    PVC)
      W=173
      hr $W
      printf "%-48s  %-34s  %-44s  %-8s  %-18s  %-11s\n" \
        "POD" "VOLUME NAME" "CLAIM" "ACCESS" "STORAGECLASS" "SIZE"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name claim access sc size; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-44s  %-8s  %-18s  %-11s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)" \
            "$(trunc "$claim"    44)" "$access" "$(trunc "$sc" 18)" "$size"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-44s  %-8s  %-18s  %-11s\n" \
            "" "$(trunc "$vol_name" 34)" \
            "$(trunc "$claim"    44)" "$access" "$(trunc "$sc" 18)" "$size"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r --argjson pm "$PVC_MAP" '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.persistentVolumeClaim) |
          . as $vol |
          ($pm[$vol.persistentVolumeClaim.claimName] //
             {accessModes:"-",storageClass:"-",size:"?"}) as $p |
          [ $pod.metadata.name, $vol.name,
            $vol.persistentVolumeClaim.claimName,
            $p.accessModes, $p.storageClass, $p.size ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── GeV: POD(48) VOL(34) ACCESS(8) SC(18) SIZE(11) = 127 ────────────────
    GeV)
      W=127
      hr $W
      printf "%-48s  %-34s  %-8s  %-18s  %-11s\n" \
        "POD" "VOLUME NAME" "ACCESS" "STORAGECLASS" "SIZE"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name access sc size; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-8s  %-18s  %-11s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)" \
            "$access" "$(trunc "$sc" 18)" "$size"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-8s  %-18s  %-11s\n" \
            "" "$(trunc "$vol_name" 34)" \
            "$access" "$(trunc "$sc" 18)" "$size"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r --argjson pm "$PVC_MAP" '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.ephemeral) |
          . as $vol |
          (.ephemeral.volumeClaimTemplate.spec) as $spec |
          ($pm[($pod.metadata.name + "-" + $vol.name)] // {
            accessModes: ($spec.accessModes | map(
              if   . == "ReadWriteMany"    then "RWX"
              elif . == "ReadWriteOnce"    then "RWO"
              elif . == "ReadOnlyMany"     then "ROX"
              elif . == "ReadWriteOncePod" then "RWOP"
              else . end) | join("/")),
            storageClass: ($spec.storageClassName // "-"),
            size:         ($spec.resources.requests.storage // "?")
          }) as $info |
          [ $pod.metadata.name, $vol.name,
            $info.accessModes, $info.storageClass, $info.size ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── hostPath: POD(48) VOL(34) PATH(46) HOST_TYPE(12) = 146 ──────────────
    hostPath)
      W=146
      hr $W
      printf "%-48s  %-34s  %-46s  %-12s\n" \
        "POD" "VOLUME NAME" "PATH" "HOST TYPE"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name path htype; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-46s  %-12s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)" \
            "$(trunc "$path" 46)" "$htype"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-46s  %-12s\n" \
            "" "$(trunc "$vol_name" 34)" \
            "$(trunc "$path" 46)" "$htype"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.hostPath) |
          [ $pod.metadata.name, .name,
            .hostPath.path, (.hostPath.type // "unset") ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── emptyDir: POD(48) VOL(34) SIZE_LIMIT(11) MEDIUM(8) = 107 ────────────
    emptyDir)
      W=107
      hr $W
      printf "%-48s  %-34s  %-11s  %-8s\n" \
        "POD" "VOLUME NAME" "SIZE LIMIT" "MEDIUM"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name size medium; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-11s  %-8s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)" \
            "$size" "$medium"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-11s  %-8s\n" \
            "" "$(trunc "$vol_name" 34)" \
            "$size" "$medium"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.emptyDir) |
          [ $pod.metadata.name, .name,
            (.emptyDir.sizeLimit // "unlimited"),
            (.emptyDir.medium    // "-") ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── configMap: POD(48) VOL(34) CONFIGMAP(44) = 130 ───────────────────────
    configMap)
      W=130
      hr $W
      printf "%-48s  %-34s  %-44s\n" \
        "POD" "VOLUME NAME" "CONFIGMAP"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name cm_name; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-44s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)" \
            "$(trunc "$cm_name"  44)"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-44s\n" \
            "" "$(trunc "$vol_name" 34)" "$(trunc "$cm_name" 44)"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.configMap) |
          [ $pod.metadata.name, .name, (.configMap.name // "-") ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── secret: POD(48) VOL(34) SECRET(44) = 130 ─────────────────────────────
    secret)
      W=130
      hr $W
      printf "%-48s  %-34s  %-44s\n" \
        "POD" "VOLUME NAME" "SECRET"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name secret_name; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-44s\n" \
            "$(trunc "$pod_name"    48)" "$(trunc "$vol_name" 34)" \
            "$(trunc "$secret_name" 44)"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-44s\n" \
            "" "$(trunc "$vol_name" 34)" "$(trunc "$secret_name" 44)"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.secret) |
          [ $pod.metadata.name, .name, (.secret.secretName // "-") ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── projected: POD(48) VOL(34) SOURCES(30) = 116 ─────────────────────────
    projected)
      W=116
      hr $W
      printf "%-48s  %-34s  %-30s\n" \
        "POD" "VOLUME NAME" "SOURCES"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name sources; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s  %-30s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)" \
            "$(trunc "$sources"  30)"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s  %-30s\n" \
            "" "$(trunc "$vol_name" 34)" "$(trunc "$sources" 30)"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.projected) |
          [ $pod.metadata.name, .name,
            (.projected.sources | map(keys[0]) | join(", ")) ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

    # ── downwardAPI: POD(48) VOL(34) = 84 ────────────────────────────────────
    downwardAPI)
      W=84
      hr $W
      printf "%-48s  %-34s\n" "POD" "VOLUME NAME"
      hr $W
      while IFS=$'\t' read -r pod_name vol_name; do
        # shellcheck disable=SC2254
        [[ -n "$POD_PATTERN" && "$pod_name" != $POD_PATTERN ]] && continue
        if [[ "$pod_name" != "$last_pod" ]]; then
          [[ -n "$last_pod" ]] && echo ""
          printf "%-48s  %-34s\n" \
            "$(trunc "$pod_name" 48)" "$(trunc "$vol_name" 34)"
          last_pod="$pod_name"
        else
          printf "%-48s  %-34s\n" "" "$(trunc "$vol_name" 34)"
        fi
        matched=$(( matched + 1 ))
      done < <(jq -r '
        [ .items[] | . as $pod |
          .spec.volumes[]? | select(.downwardAPI) |
          [ $pod.metadata.name, .name ] ] |
        sort_by(.[0], .[1]) | .[] | @tsv
      ' <<< "$PODS_JSON")
      ;;

  esac

  hr $W
  echo "" >&2
  printf "%d matching volume(s) found.\n" "$matched" >&2
}

# ─── MODE 5: PVC lookup — claim stats + CSI location + pod consumer table ─────
# -c CLAIM_NAME  Lists key PVC/PV stats and every pod referencing the claim.
#                Running pods are sorted first; phase-exited pods follow.
print_pvc_report() {
  # Locate the PVC in the already-fetched namespace data
  local pvc_json
  pvc_json=$(jq --arg c "$CLAIM_NAME" '.items[] | select(.metadata.name == $c)' <<< "$PVCS_JSON")
  [[ -z "$pvc_json" ]] && die "PVC '$CLAIM_NAME' not found in namespace '$NAMESPACE'"

  # Parse fixed PVC fields
  local pvc_status pvc_access pvc_sc pvc_size pvc_pv pvc_created
  IFS=$'\t' read -r pvc_status pvc_access pvc_sc pvc_size pvc_pv pvc_created < <(jq -r '
    [ .status.phase,
      (.status.accessModes // .spec.accessModes | map(
        if   . == "ReadWriteMany"    then "RWX"
        elif . == "ReadWriteOnce"    then "RWO"
        elif . == "ReadOnlyMany"     then "ROX"
        elif . == "ReadWriteOncePod" then "RWOP"
        else . end) | join("/")),
      (.spec.storageClassName // "-"),
      (.status.capacity.storage // .spec.resources.requests.storage // "?"),
      (.spec.volumeName // "-"),
      .metadata.creationTimestamp
    ] | @tsv
  ' <<< "$pvc_json")

  # Fetch the backing PV (cluster-scoped — requires a separate kubectl call)
  local pv_json="" pv_reclaim="-" csi_driver="-"
  if [[ "$pvc_pv" != "-" ]]; then
    pv_json=$(kubectl get pv "$pvc_pv" -o json 2>/dev/null) || true
  fi
  if [[ -n "$pv_json" ]]; then
    IFS=$'\t' read -r pv_reclaim csi_driver < <(jq -r '
      [ (.spec.persistentVolumeReclaimPolicy // "-"),
        (.spec.csi.driver // "-")
      ] | @tsv
    ' <<< "$pv_json")
  fi

  # ── Header block ─────────────────────────────────────────────────────────────
  local HW=80
  echo ""
  printf "PVC Report — %s  namespace: %s\n" "$CLAIM_NAME" "$NAMESPACE"
  hr $HW
  printf "  %-22s %s\n" "Claim:"          "$CLAIM_NAME"
  printf "  %-22s %s\n" "Status:"         "$pvc_status"
  printf "  %-22s %s\n" "Access Mode:"    "$pvc_access"
  printf "  %-22s %s\n" "Storage Class:"  "$pvc_sc"
  printf "  %-22s %s\n" "Size:"           "$pvc_size"
  printf "  %-22s %s\n" "Volume (PV):"    "$pvc_pv"
  printf "  %-22s %s\n" "Reclaim Policy:" "$pv_reclaim"
  printf "  %-22s %s\n" "CSI Driver:"     "$csi_driver"

  # Dynamic CSI volumeAttributes — strip internal k8s bookkeeping keys
  # Indented 2 extra spaces (values stay column-aligned with the rest of the header)
  if [[ -n "$pv_json" ]]; then
    while IFS=$'\t' read -r key val; do
      printf "    %-20s %s\n" "${key}:" "$val"
    done < <(jq -r '
      .spec.csi.volumeAttributes // {} | to_entries |
      map(select(
        (.key | startswith("csi.storage.k8s.io/")   | not) and
        (.key | startswith("storage.kubernetes.io/") | not)
      )) | .[] | [.key, .value] | @tsv
    ' <<< "$pv_json")
  fi

  printf "  %-22s %s\n" "Created:" "$pvc_created"

  # ── Pod consumer table ───────────────────────────────────────────────────────
  # Columns (2-space indent): POD(48)  STATE(10)  NODE(32)  MOUNT PATH(40) = 138
  local TW=138
  echo ""
  hr $TW
  printf "  %-48s  %-10s  %-32s  %-40s\n" "POD" "STATE" "NODE" "MOUNT PATH"
  hr $TW

  local total=0 running=0 state
  while IFS=$'\t' read -r pod_name phase node paths; do
    if [[ "$phase" == "Running" ]]; then
      state="Running"
      running=$(( running + 1 ))
    else
      state="Completed"
    fi
    printf "  %-48s  %-10s  %-32s  %-40s\n" \
      "$(trunc "$pod_name" 48)" "$state" \
      "$(trunc "$node"     32)" \
      "$(trunc "$paths"    40)"
    total=$(( total + 1 ))
  done < <(jq -r --arg claim "$CLAIM_NAME" '
    [ .items[] | . as $pod |
      .spec.volumes[]? | select(.persistentVolumeClaim.claimName == $claim) | . as $vol |
      ( [ $pod.spec.containers[]? | .volumeMounts[]? |
            select(.name == $vol.name) | .mountPath
        ] | unique | join(", ") ) as $paths |
      { sk:  (if ($pod.status.phase // "") == "Running" then 0 else 1 end),
        row: [ $pod.metadata.name,
               ($pod.status.phase // "Unknown"),
               ($pod.spec.nodeName // "-"),
               (if $paths == "" then "-" else $paths end) ] }
    ] | sort_by(.sk, .row[0]) | .[] | .row | @tsv
  ' <<< "$PODS_JSON")

  hr $TW
  echo "" >&2
  printf "%d pod(s) found.  %d running.\n" "$total" "$running" >&2
}

# ─── Main ─────────────────────────────────────────────────────────────────────
if [[ -n "$CLAIM_NAME" ]]; then
  print_pvc_report
  exit 0
fi

if [[ -n "$VOL_TYPE" ]]; then
  print_type_report
  exit 0
fi

if [[ -z "$POD_PATTERN" ]]; then
  print_namespace_summary
  exit 0
fi

# Determine whether the pattern contains glob metacharacters
is_glob=false
[[ "$POD_PATTERN" == *'*'* || "$POD_PATTERN" == *'?'* || "$POD_PATTERN" == *'['* ]] \
  && is_glob=true

matched=0
while IFS= read -r pod_name; do
  # shellcheck disable=SC2254   # glob variable on right side is intentional
  if [[ "$pod_name" == $POD_PATTERN ]]; then
    pod_json=$(jq --arg n "$pod_name" '.items[] | select(.metadata.name == $n)' <<< "$PODS_JSON")
    if $is_glob; then
      print_pod_storage "$pod_name" "$pod_json"
    else
      print_pod_detail  "$pod_name" "$pod_json"
    fi
    matched=$(( matched + 1 ))
  fi
done < <(jq -r '.items[].metadata.name' <<< "$PODS_JSON")

echo "" >&2

if (( matched == 0 )); then
  echo "No pods matched: '$POD_PATTERN'" >&2
  exit 1
fi

echo "Matched ${matched} pod(s)." >&2