#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Script to identify and delete EFS file systems with user approval
# Usage: ./delete-efs.sh

set -e

echo "=== EFS Deletion Script ==="
echo

# Get all EFS file systems
echo "Identifying EFS file systems..."
filesystems=$(aws efs describe-file-systems --query 'FileSystems[*].[FileSystemId,Name,LifeCycleState,NumberOfMountTargets]' --output text)

if [ -z "$filesystems" ]; then
    echo "No EFS file systems found."
    exit 0
fi

# Display file systems
echo "Found EFS file systems:"
echo "ID                    Name                  State       Mount Targets"
echo "-------------------------------------------------------------------"
echo "$filesystems"
echo

# Get file system ID from user
read -p "Enter the File System ID to delete: " fs_id

if [ -z "$fs_id" ]; then
    echo "No file system ID provided. Exiting."
    exit 1
fi

# Validate the file system exists
echo "Validating file system $fs_id..."
fs_info=$(aws efs describe-file-systems --file-system-id "$fs_id" --query 'FileSystems[0].[FileSystemId,Name,LifeCycleState]' --output text 2>/dev/null || echo "")

if [ -z "$fs_info" ]; then
    echo "Error: File system $fs_id not found."
    exit 1
fi

# Get mount targets for this file system
echo "Getting mount targets for $fs_id..."
mount_targets=$(aws efs describe-mount-targets --file-system-id "$fs_id" --query 'MountTargets[*].[MountTargetId,LifeCycleState]' --output text)

# Display what will be deleted
echo
echo "=== DELETION PLAN ==="
echo "File System: $fs_info"
if [ -n "$mount_targets" ]; then
    echo "Mount Targets to delete:"
    echo "ID                    State"
    echo "-------------------------"
    echo "$mount_targets"
else
    echo "No mount targets found."
fi
echo

# Get user confirmation
read -p "Are you sure you want to delete this EFS file system? This is IRREVERSIBLE! (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Deletion cancelled."
    exit 0
fi

echo
echo "=== EXECUTING DELETION ==="

# Delete mount targets first
if [ -n "$mount_targets" ]; then
    echo "Deleting mount targets..."
    while IFS=$'\t' read -r mt_id mt_state; do
        if [ -n "$mt_id" ]; then
            echo "  Deleting mount target: $mt_id"
            aws efs delete-mount-target --mount-target-id "$mt_id"
        fi
    done <<< "$mount_targets"
    
    # Wait for mount targets to be deleted
    echo "Waiting for mount targets to be deleted..."
    while true; do
        remaining=$(aws efs describe-mount-targets --file-system-id "$fs_id" --query 'length(MountTargets)' --output text 2>/dev/null || echo "0")
        if [ "$remaining" = "0" ]; then
            break
        fi
        echo "  Still waiting... ($remaining mount targets remaining)"
        sleep 5
    done
    echo "  All mount targets deleted."
fi

# Delete the file system
echo "Deleting file system: $fs_id"
aws efs delete-file-system --file-system-id "$fs_id"

echo
echo "=== DELETION COMPLETE ==="
echo "EFS file system $fs_id has been deleted."