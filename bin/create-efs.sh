#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Script to create EFS file system
# Usage: ./create-efs.sh

## My Prefix (useful for naming things in AWS)
export MY_PREFIX=${MY_PREFIX:-"YOUR_PREFIX_HERE"}

# find VPC for the EKS cluster
VPC_ID=$(aws eks describe-cluster --name ${MY_PREFIX}-eks --query 'cluster.resourcesVpcConfig.vpcId' --output text --no-cli-pager)


echo "Using VPC ID: $VPC_ID"

# Create EFS file system
echo "Creating EFS file system..."
EFS_ID=$(aws efs create-file-system \
    --performance-mode generalPurpose \
    --encrypted \
    --tags Key=Name,Value=${MY_PREFIX}-efs Key=Project,Value=Your_Project_Name \
    --query 'FileSystemId' \
    --output text \
    --no-cli-pager)

echo "Created EFS file system: $EFS_ID"

# Get unique subnet IDs where EKS nodes are running
echo "Getting subnet IDs..."
SUBNET_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/${MY_PREFIX}-eks,Values=owned" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].SubnetId' \
    --output text \
    --no-cli-pager | tr '\t' '\n' | sort -u | tr '\n' ' ')

echo "Found unique subnets: $SUBNET_IDS"

# Get security group for EKS nodes - try multiple approaches
NODE_SECURITY_GROUP=$(aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/${MY_PREFIX}-eks,Values=owned" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].SecurityGroups[?contains(GroupName, `node`) || contains(GroupName, `NodeInstanceRole`)].GroupId' \
    --output text \
    --no-cli-pager | head -1)

# If no node-specific security group found, use any security group from the instances
if [ -z "$NODE_SECURITY_GROUP" ]; then
    NODE_SECURITY_GROUP=$(aws ec2 describe-instances \
        --filters "Name=tag:kubernetes.io/cluster/${MY_PREFIX}-eks,Values=owned" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].SecurityGroups[0].GroupId' \
        --output text \
        --no-cli-pager | head -1)
fi

echo "Using security group: $NODE_SECURITY_GROUP"

# Wait for EFS to be available 
echo "Waiting for EFS file system to be available..."
while true; do
    STATE=$(aws efs describe-file-systems --file-system-id $EFS_ID --query 'FileSystems[0].LifeCycleState' --output text --no-cli-pager)
    if [ "$STATE" = "available" ]; then
        echo "EFS file system is now available"
        break
    fi
    echo "Current state: $STATE - waiting..."
    sleep 5
done

# Create mount targets in each unique subnet
for SUBNET_ID in $SUBNET_IDS; do
    echo "Creating mount target in subnet: $SUBNET_ID"
    
    # Check if mount target already exists in this subnet
    EXISTING_MT=$(aws efs describe-mount-targets --file-system-id $EFS_ID --query "MountTargets[?SubnetId=='$SUBNET_ID'].MountTargetId" --output text --no-cli-pager)
    
    if [ -n "$EXISTING_MT" ]; then
        echo "  Mount target already exists in subnet $SUBNET_ID: $EXISTING_MT"
        continue
    fi
    
    # Create mount target with error handling
    if [ -n "$NODE_SECURITY_GROUP" ]; then
        aws efs create-mount-target \
            --file-system-id $EFS_ID \
            --subnet-id $SUBNET_ID \
            --security-groups $NODE_SECURITY_GROUP \
            --no-cli-pager && echo "  Successfully created mount target in $SUBNET_ID" || echo "  Failed to create mount target in $SUBNET_ID"
    else
        # Create without security group and let it use default
        aws efs create-mount-target \
            --file-system-id $EFS_ID \
            --subnet-id $SUBNET_ID \
            --no-cli-pager && echo "  Successfully created mount target in $SUBNET_ID (default SG)" || echo "  Failed to create mount target in $SUBNET_ID"
    fi
done

# Wait for mount targets to be available
echo "Waiting for mount targets to be available..."
while true; do
    MT_STATES=$(aws efs describe-mount-targets --file-system-id $EFS_ID --query 'MountTargets[].LifeCycleState' --output text --no-cli-pager)
    if echo "$MT_STATES" | grep -q "creating"; then
        echo "Some mount targets still creating - waiting..."
        sleep 5
    else
        echo "All mount targets are ready"
        break
    fi
done

# Show final status
echo "=== EFS Setup Complete ==="
echo "EFS File System ID: $EFS_ID"
echo "Mount Targets:"
aws efs describe-mount-targets --file-system-id $EFS_ID --query 'MountTargets[].[SubnetId,LifeCycleState,IpAddress,AvailabilityZoneName]' --output table --no-cli-pager

echo ""
echo "Export this for use in storage class:"
echo "export EFS_ID=$EFS_ID"
