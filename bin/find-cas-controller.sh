#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Script to find the newest sas-cas-server-default-controller pod and locate its storage paths (CAS Disk Cache & emptydir)
# Usage: ./find-cas-controller.sh

set -e

echo "🔍 Finding newest sas-cas-server-default-controller pod..."

# Find all sas-cas-server-default-controller pods and get the newest one with proper output format
NEWEST_POD_INFO=$(kubectl get pods -A -o wide | grep sas-cas-server-default-controller | sort -k6,6 | tail -1)

if [ -z "$NEWEST_POD_INFO" ]; then
    echo "❌ No sas-cas-server-default-controller pods found!"
    exit 1
fi

# Extract pod name, namespace, and node
NAMESPACE=$(echo "$NEWEST_POD_INFO" | awk '{print $1}')
POD_NAME=$(echo "$NEWEST_POD_INFO" | awk '{print $2}')
NODE_NAME=$(echo "$NEWEST_POD_INFO" | awk '{print $8}')

echo "✅ Found pod: $POD_NAME (namespace: $NAMESPACE, node: $NODE_NAME)"

# Get PVC information - find any PVC associated with this pod (looking for CAS Disk Cache)
PVC_INFO=$(kubectl get pvc -n "$NAMESPACE" | grep "$POD_NAME" | head -1)

if [ -n "$PVC_INFO" ]; then
    PVC_NAME=$(echo "$PVC_INFO" | awk '{print $1}')
    PV_NAME=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
    LOCAL_PATH=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.hostPath.path}')
    # Get the parent directory for CAS Disk Cache
    LOCAL_PATH_ROOT=$(dirname "$LOCAL_PATH")
fi

# Get emptydir information
POD_UID=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')
EMPTYDIR_PATH="/var/lib/kubelet/pods/$POD_UID/volumes/kubernetes.io~empty-dir"

echo ""
echo "🚀 ACCESS COMMANDS:"
echo ""
echo "# Interactive shell on node:"
echo "-----------------------------------------------------------------"
echo "kubectl debug node/$NODE_NAME -it --image=busybox -- chroot /host"
echo "-----------------------------------------------------------------"
echo "# Alternative: kubectl debug node/$NODE_NAME -it --image=nicolaka/netshoot -- chroot /host"
echo ""

if [ -n "$LOCAL_PATH_ROOT" ]; then
    echo "# CAS Disk Cache volumes:"
    echo "cd $LOCAL_PATH_ROOT"
    echo ""
fi

echo "# EmptyDir volumes:"
echo "cd $EMPTYDIR_PATH"
echo ""
echo "# Clean up debug pods:"
echo "kubectl get pods | grep node-debugger | awk '{print \$1}' | xargs kubectl delete pod"
echo ""