#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# IMPORTANT USE INFO -------------------------------------------------------
# This script installs the Google Filestore CSI driver and the associated default storage classes.
# Use those storage classes to dynamically provision Filestore-backed PersistentVolumes --
# which means that *each* volume is its own Filestore instance. For Basic HDD service level, 
# each instance is 1Ti minimum. For SSD service level, each instance is 2.5Ti minimum.

# The viya4-iac-gcp project can create a Filestore instance, but does not provide a CSI driver
# to use it. So, instead of using the Filestore storage classes, deploy the NFS CSI driver instead.
#
# In other words, YOU PROBABLY DO NOT WANT TO RUN THIS SCRIPT unless you specifically need
# the Filestore CSI driver and its storage classes to dynamically provision multiple RWX volumes.
# --------------------------------------------------------------------------

# Install (enable) the GKE Filestore CSI addon and bind Workload Identity in one pass.
# Strategy for reliability on first run:
# 1) Ensure GSA and required IAM (roles/file.editor).
# 2) Pre-create and annotate the known kube-system KSAs used by the managed addon
#    so WI is in place before the addon starts.
# 3) Enable the addon and wait for controller/daemonset to become Ready.
# 4) Post-verify and, as a safety net, bind WI to any discovered Filestore KSAs.
# Idempotent and safe to re-run.

: "${FILESTORE_GSA_NAME:=filestore-csi-driver-sa}"
: "${FILESTORE_PRECREATE_KSAS:=1}"   # 1=pre-create kube-system KSAs before enabling addon
:

need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: missing dependency: $1"; exit 1; }; }
need kubectl; need gcloud; need jq

log() { printf '%s\n' "$*"; }

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
[[ -n "$PROJECT_ID" ]] || { log "Error: gcloud project not set. Run: gcloud config set project <PROJECT_ID>"; exit 1; }

# Ensure cluster reachable
kubectl cluster-info >/dev/null

CLUSTER_NAME=$(kubectl config current-context)
CLUSTER_LOCATION=$(gcloud container clusters list --project="$PROJECT_ID" --filter="name=${CLUSTER_NAME}" --format="value(location)" 2>/dev/null || true)
[[ -n "$CLUSTER_LOCATION" ]] || { log "Error: could not determine location for cluster ${CLUSTER_NAME}"; exit 1; }

log "Project: $PROJECT_ID | Cluster: $CLUSTER_NAME | Location: $CLUSTER_LOCATION"

# Warn if Workload Identity not enabled (we won't enable it here)
WI_POOL=$(gcloud container clusters describe "$CLUSTER_NAME" --location="$CLUSTER_LOCATION" --project="$PROJECT_ID" --format="value(workloadIdentityConfig.workloadPool)" 2>/dev/null || true)
if [[ -z "$WI_POOL" ]]; then
  log "Warning: Workload Identity is not enabled on this cluster; provisioning may fail."
fi

# Ensure Filestore API is enabled (idempotent)
if ! gcloud services list --enabled --format="value(config.name)" | grep -q '^file.googleapis.com$'; then
  log "Enabling Filestore API (file.googleapis.com)"
  gcloud services enable file.googleapis.com --project "$PROJECT_ID" >/dev/null
fi

GSA_EMAIL="${FILESTORE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

ensure_gsa() {
  if ! gcloud iam service-accounts describe "$GSA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "Creating GSA: ${FILESTORE_GSA_NAME}"
    gcloud iam service-accounts create "$FILESTORE_GSA_NAME" \
      --display-name="Filestore CSI Driver Service Account" \
      --project="$PROJECT_ID" >/dev/null
  fi
  # Wait for eventual consistency
  for i in {1..20}; do
    gcloud iam service-accounts describe "$GSA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1 && break
    sleep 2
  done
  # Ensure project-level role
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/file.editor" >/dev/null || true
}

bind_wi() {
  local ns="$1" ksa="$2"
  [[ -z "$ns" || -z "$ksa" ]] && return 0
  log "Binding WI: ${ns}/${ksa} -> ${GSA_EMAIL}"
  # Ensure SA exists (create if missing to allow annotation before addon rolls out)
  kubectl get sa "$ksa" -n "$ns" >/dev/null 2>&1 || kubectl create sa "$ksa" -n "$ns" >/dev/null 2>&1 || true
  kubectl annotate sa "$ksa" -n "$ns" \
    "iam.gke.io/gcp-service-account=${GSA_EMAIL}" --overwrite >/dev/null 2>&1 || true
  gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${ns}/${ksa}]" \
    --project="$PROJECT_ID" >/dev/null || true
}

wait_csidriver() {
  for i in {1..60}; do
    kubectl get csidriver filestore.csi.storage.gke.io >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}

wait_deploy_available() {
  local ns="$1" name="$2"
  kubectl -n "$ns" wait deploy/"$name" --for=condition=Available --timeout=600s >/dev/null 2>&1 || true
}

wait_ds_ready() {
  local ns="$1" name="$2"
  for i in {1..120}; do
    local desired ready
    desired=$(kubectl -n "$ns" get ds "$name" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
    ready=$(kubectl -n "$ns" get ds "$name" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
    if [[ "$desired" != "" && "$desired" -gt 0 && "$ready" -eq "$desired" ]]; then
      return 0
    fi
    sleep 5
  done
  return 1
}

main() {
  log "Step 1/4: Ensure GSA and IAM"
  ensure_gsa

  log "Step 2/4: Pre-bind known KSAs in kube-system (so WI is ready before addon starts)"
  if [[ "$FILESTORE_PRECREATE_KSAS" == "1" ]]; then
    bind_wi kube-system filestore-lockrelease-controller-sa
    bind_wi kube-system filestorecsi-node-sa
  else
    log "- Skipping pre-create of KSAs (FILESTORE_PRECREATE_KSAS!=1)"
  fi

  log "Step 3/4: Enable Filestore CSI addon - this will take several minutes..."
  gcloud container clusters update "$CLUSTER_NAME" \
    --location="$CLUSTER_LOCATION" \
    --project="$PROJECT_ID" \
    --update-addons=GcpFilestoreCsiDriver=ENABLED >/dev/null

  log "Step 4/4: Verify addon rollout and finalize WI"
  wait_csidriver || log "- CSIDriver not observed yet (continuing)"
  wait_deploy_available kube-system filestore-lock-release-controller
  wait_ds_ready kube-system filestore-node || true

  # Safety net: if addon used different KSA names, discover and bind them too
  JSON=$(kubectl get deploy,ds -A -o json 2>/dev/null || echo '{"items":[]}')
  if [[ -n "$JSON" ]]; then
    echo "$JSON" | jq -r '
      .items
      | map(select((.metadata.name|test("filestore"; "i")) and (.spec.template.spec.serviceAccountName!=null)))
      | .[] | "\(.metadata.namespace) \(.spec.template.spec.serviceAccountName)"' |
    while read -r ns ksa; do
      [[ -z "$ns" || -z "$ksa" ]] && continue
      bind_wi "$ns" "$ksa"
    done
  fi
  log "CSI Verification:";
  kubectl get csidriver filestore.csi.storage.gke.io || true
  kubectl -n kube-system get deploy filestore-lock-release-controller -o wide 2>/dev/null || true
  kubectl -n kube-system get ds filestore-node -o wide 2>/dev/null || true
  kubectl get pods -A | grep -i filestore || true

  log "Storage Classes Verification:"
  kubectl get storageclass \
   -o=custom-columns=NAME:.metadata.name,TIER:.parameters.tier,PROVISIONER:.provisioner | head -1
  kubectl get storageclass \
   -o=custom-columns=NAME:.metadata.name,TIER:.parameters.tier,PROVISIONER:.provisioner \
   | grep filestore.csi.storage.gke.io

  log "Complete. Filestore CSI addon is enabled and Workload Identity is bound."

  # Note, when creating your own storage classes for Filestore, be sure to specify your VPC:
  #  # Specify our VPC
  #  yq eval ".parameters.network = \"${MY_PREFIX}-vpc\"" -i defineSC_viya-shared-sc.yaml
  #
  # Else, the default VPC will be used which likely isn't accessible from your GKE cluster VPC

}

main "$@"