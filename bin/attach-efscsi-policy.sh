#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
# This script attaches the AmazonEFSCSIDriverPolicy to the IAM role associated
# with each of the K8s worker nodes in an EKS cluster.
#
# The script will loop through each worker node instance ID and get the IAM
# instance profile information. It will then get the IAM role name associated
# with the instance profile and attach the AmazonEFSCSIDriverPolicy to the role.
#
# The script requires the AWS CLI to be installed and configured with the
# necessary permissions to attach policies to IAM roles.
#
# Usage: ./attach-efscsi-policy.sh
################################################################################
set -eo pipefail

#shopt -s expand_aliases

# Set your EKS cluster name
CLUSTER_NAME="${MY_PREFIX}-eks"

EFS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"

# Get the list of worker node instance IDs for the cluster
WORKER_INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].InstanceId' --output json --no-cli-pager  | grep "i-" | awk -F\" '{ print $2 }')

if [ -z "$WORKER_INSTANCE_IDS" ]; then
  echo "Warning: No running worker nodes found for cluster '$CLUSTER_NAME'."
  echo "Please ensure your worker nodes are running."
  exit 1
fi

echo -e "Found worker node instance IDs:\n$WORKER_INSTANCE_IDS"

# Loop through each worker node instance ID
for INSTANCE_ID in $WORKER_INSTANCE_IDS; do
  echo -e "\nProcessing instance ID ${INSTANCE_ID}: "

  # Get the IAM instance profile information for the current instance
  INSTANCE_PROFILE_INFO=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[*].Instances[*].IamInstanceProfile.Id' --output json | grep '"' | awk -F\" '{ print $2 }')
  INSTANCE_PROFILE_ARN=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[*].Instances[*].IamInstanceProfile.Arn' --output json | grep '"' | awk -F\" '{ print $2 }')
  INSTANCE_PROFILE_NAME=$(echo  $INSTANCE_PROFILE_ARN | awk -F/ '{print $2}')

  if [ -z "$INSTANCE_PROFILE_INFO" ]; then
    echo "Warning: Could not find IAM instance profile ID for instance '$INSTANCE_ID'."
    continue
  fi

  # Now, let's get the IAM role name associated with this instance profile ID
  IAM_ROLE_NAME=$(aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --query 'InstanceProfile.Roles[*].Arn' --output text  | awk -F/ '{ print $2 }')

  if [ -z "$IAM_ROLE_NAME" ]; then
    echo "Warning: Could not find IAM role name for instance profile ARN '$INSTANCE_PROFILE_ARN'."
    continue
  fi

  echo "  IAM Role Name: $IAM_ROLE_NAME"

  # Check if the policy is already attached to the role
  POLICY_ATTACHED=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE_NAME" --query "AttachedPolicies[?PolicyArn=='$EFS_CSI_POLICY_ARN'].PolicyArn" --output text 2>/dev/null)

  if [ -z "$POLICY_ATTACHED" ]; then
    echo "  Attaching AmazonEFSCSIDriverPolicy to role '$IAM_ROLE_NAME'..."
    echo "  >> aws iam attach-role-policy --role-name \"$IAM_ROLE_NAME\" --policy-arn \"$EFS_CSI_POLICY_ARN\"" 
    aws iam attach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn "$EFS_CSI_POLICY_ARN" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "  Successfully attached AmazonEFSCSIDriverPolicy to role '$IAM_ROLE_NAME'."
    else
      echo "  Error attaching AmazonEFSCSIDriverPolicy to role '$IAM_ROLE_NAME'."
    fi
  else
    echo "  AmazonEFSCSIDriverPolicy is already attached to role '$IAM_ROLE_NAME'."
  fi
done

echo "Finished attaching AmazonEFSCSIDriverPolicy to k8s worker nodes in cluster '$CLUSTER_NAME'."