#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Function to copy a storage class YAML
copysc() {
    # Check for the correct number of arguments
    if [ "$#" -ne 2 ]; then
        echo "Usage: copysc <source_storage_class> <new_storage_class_name>"
        return 1
    fi

    local SOURCE_SC=$1
    local NEW_SC=$2
    local NEW_YAML="defineSC_${NEW_SC}.yaml"

    # Use yq to get the source YAML, modify it, and save it to the new file
    kubectl get sc "${SOURCE_SC}" -o yaml | yq eval "
        .metadata.name = \"${NEW_SC}\" |
        del(.metadata.resourceVersion) |
        del(.metadata.uid) |
        del(.metadata.creationTimestamp) |
        del(.metadata.selfLink) |
        del(.metadata.annotations)
    " - > "${NEW_YAML}"

    # Check if the new YAML file was created successfully
    if [ ! -f "${NEW_YAML}" ]; then
        echo "Failed to create ${NEW_YAML}. Exiting."
        return 1
    fi

    echo -e "\n---\n  Created: ${NEW_YAML}\n"
    echo -e "To deploy: kubectl apply -f ${NEW_YAML}\n---\n"
}

# If script is run directly (not sourced), call the function with arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    copysc "$@"
fi