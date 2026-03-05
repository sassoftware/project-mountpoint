#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Create daemonSet to format and mount local NVMe drives
# Expects an identifying label has been applied to nodes to determine which has local disk.

NODE_SELECTOR_LABEL="attr.sas.com/local-nvme: \"true\""

cd ~/viya4-iac-aws

# -- Start DaemonSet YAML for mounting local NVMe SSD
# -- Heredoc to resolve variable inside the file
cat << EOF > ./nvme-mounter-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvme-mounter
  namespace: kube-system
  labels:
    app: nvme-mounter
spec:
  selector:
    matchLabels:
      app: nvme-mounter
  template:
    metadata:
      labels:
        app: nvme-mounter
    spec:
      nodeSelector:
        ${NODE_SELECTOR_LABEL}
      hostPID: true
      hostNetwork: true
EOF

# -- Append the rest of the DaemonSet YAML
# -- Heredoc to avoid variable resolution inside the file
cat << 'EOF' >> ./nvme-mounter-daemonset.yaml
      tolerations:
      - operator: Exists
      containers:
      - name: nvme-mounter
        image: alpine:3.18
        securityContext:
          privileged: true
        command: ["/bin/sh"]
        args:
        - -c
        - |
          set -euo pipefail

          # Use host tools via nsenter
          NSENTER="nsenter -t 1 -m -u -n -p --"

          MOUNT_POINT="/viya-scratch"
          LABEL="VIYA_SCRATCH"

          echo "Starting NVMe setup for SAS Viya ephemeral storage..."

          # Auto-detect NVMe device: find the first NVMe disk that's not already mounted
          # and is not the root device
          DEVICE=""
          for nvme_dev in $(ls -1 /host/dev/nvme*n1 2>/dev/null | sort); do
              dev_name=$(basename "$nvme_dev")
              # Skip if it's already mounted
              if ! $NSENTER mountpoint -q "/dev/$dev_name" 2>/dev/null; then
                  DEVICE="/dev/$dev_name"
                  break
              fi
          done

          if [ -z "$DEVICE" ]; then
              # Fallback: try to detect from within container context
              DEVICE=$($NSENTER lsblk -d -n -l -o NAME,TYPE | grep nvme | head -1 | awk '{print "/dev/"$1}')
          fi

          if [ -z "$DEVICE" ]; then
              echo "ERROR: No available NVMe device found"
              exit 1
          fi

          echo "Found NVMe device: ${DEVICE}"

          # Verify device exists in host namespace
          if ! $NSENTER test -b "${DEVICE}"; then
              echo "ERROR: Device ${DEVICE} is not a block device in host namespace"
              exit 1
          fi

          # Skip partitioning - format the entire device directly
          echo "Checking if device is already formatted..."
          if ! $NSENTER blkid "${DEVICE}" 2>/dev/null | grep -q xfs; then
              echo "Formatting entire device with XFS: ${DEVICE}"
              $NSENTER mkfs.xfs -f -L "${LABEL}" "${DEVICE}"
          else
              echo "Device ${DEVICE} already formatted with XFS"
          fi

          # Create mount point if it doesn't exist (via host root mount)
          if [ ! -d "/host${MOUNT_POINT}" ]; then
              echo "Creating mount point: ${MOUNT_POINT}"
              mkdir -p "/host${MOUNT_POINT}"
          fi

          # Get UUID of the device using host blkid
          UUID=$($NSENTER blkid -s UUID -o value "${DEVICE}")

          # Check if already mounted using host mountpoint
          if ! $NSENTER mountpoint -q "${MOUNT_POINT}"; then
              echo "Mounting ${DEVICE} to ${MOUNT_POINT}"
              $NSENTER mount -t xfs -o discard,noatime "${DEVICE}" "${MOUNT_POINT}"
          else
              echo "${MOUNT_POINT} already mounted"
          fi

          # Add to fstab if not already present (via host root mount)
          if ! grep -q "${UUID}" /host/etc/fstab; then
              echo "Adding entry to /etc/fstab"
              echo "UUID=${UUID} ${MOUNT_POINT} xfs defaults,nofail,discard,noatime 0 2" >> /host/etc/fstab
          else
              echo "Entry already exists in /etc/fstab"
          fi

          # Set permissions for SAS workloads
          echo "Setting permissions on ${MOUNT_POINT}"
          $NSENTER chmod 1777 "${MOUNT_POINT}"

          echo "NVMe SSD setup completed successfully for SAS Viya"
          echo "Mount point ${MOUNT_POINT} ready for SASWORK and CAS_DISK_CACHE"
          echo "Device: ${DEVICE}, UUID: ${UUID}, Size: $($NSENTER df -h ${MOUNT_POINT} | tail -1)"

          # Keep container running to maintain mount monitoring
          echo "Monitoring mount point..."
          while true; do
              if ! $NSENTER mountpoint -q "${MOUNT_POINT}"; then
                  echo "ERROR: Mount point ${MOUNT_POINT} no longer mounted!"
                  exit 1
              fi
              sleep 30
          done
        volumeMounts:
        - name: host-root
          mountPath: /host
          mountPropagation: Bidirectional
      volumes:
      - name: host-root
        hostPath:
          path: /
      restartPolicy: Always
EOF

# And apply it
kubectl apply -f ./nvme-mounter-daemonset.yaml

echo -e "\nNVMe mounter DaemonSet deployed. Pausing for pods to be ready..."
sleep 10

# Get status on the new daemonset
kubectl get daemonsets.apps nvme-mounter

echo -e "\nDone. Confirm pods running on desired nodes."