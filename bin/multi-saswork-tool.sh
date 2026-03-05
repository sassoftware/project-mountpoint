#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# multi-saswork-tool.sh - helper for setting up multiple SASWORK providers
# Purpose: Streamlined tool to create new SASWORK configurations in SAS Viya
# 
# Usage: multi-saswork-tool.sh BASENAME STORAGE CONTEXT-TYPE CONTEXT-NAME
#   BASENAME: Base name for new resources
#   STORAGE: 'emptyDir', 'sc:storage-class-name', or 'pvc:pvc-name'
#   CONTEXT-TYPE: "compute", "batch", "connect", or "launcher"
#   CONTEXT-NAME: Name of existing context to clone from
#
# Commonly used:
# Example: multi-saswork-tool.sh fast-saswork emptyDir batch   "default"
# Example: multi-saswork-tool.sh fast-saswork emptyDir compute "SAS Studio compute context"
#
# Unlikely, special cases:
# Example: multi-saswork-tool.sh fast-saswork emptyDir connect "default-launcher"
# Example: multi-saswork-tool.sh fast-saswork emptyDir launcher "SAS Studio launcher context"
#
# Can also be sourced to use individual functions:
#   source multi-saswork-tool.sh

set -o pipefail

#==============================================================================
# Functions
#==============================================================================

# Function to create pod template with emptyDir
create_podtemplate_emptydir() {
    local source_template="$1"
    local new_template="$2"
    local output_file="${WORK_DIR}/definePT_${new_template}.json"

    # First, verify the source template has a "viya" volume
    echo "        Check pod template specifies a "viya" volume for SASWORK"

    if ! kubectl get podtemplate "${source_template}" -n "${VIYA_NS}" -o json 2>/dev/null | jq -e '.template.spec.volumes[] | select(.name == "viya")' > /dev/null 2>&1; then
        echo -e "\nERROR: Source pod template \"${source_template}\" does not have a 'viya' volume (required for SASWORK)\n"
        return 1
    fi

    echo "        Creating pod template: ${new_template} (emptyDir)"

    kubectl get podtemplate "${source_template}" -n "${VIYA_NS}" -o json | \
    jq --arg new_name "${new_template}" '.metadata.name = $new_name' | \
    jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .metadata.managedFields)' | \
    jq '(.template.spec.volumes[] | select(.name == "viya")) |= {name: "viya", emptyDir: {}}' \
    > "${output_file}"
    
    # Note: the "viya" volume is where SPRE stores SASWORK data.
    #       And fyi, the "tmp" volume is where the SPRE stores its ECE_Cache data.

    if [[ $? -ne 0 ]]; then
        echo -e "\nERROR: Failed to create ${output_file}\n"
        return 1
    fi
    
    # Verify the viya volume is emptyDir
    local vol_check=$(jq -r '.template.spec.volumes[] | select(.name == "viya") | has("emptyDir")' "${output_file}")
    if [[ "${vol_check}" != "true" ]]; then
        echo -e "\nERROR: viya volume is not emptyDir in ${output_file}\n"
        return 1
    fi
    
    # Apply to Kubernetes
    kubectl apply -f "${output_file}"
    if [[ $? -eq 0 ]]; then
        echo -e "\nPod template created successfully\n"
    else
        echo -e "\nERROR: Failed to apply pod template\n"
        return 1
    fi
}

# Function to create pod template with any storage class
create_podtemplate_sc() {
    local source_template="$1"
    local new_template="$2"
    local storage_class="$3"
    local output_file="${WORK_DIR}/definePT_${new_template}.json"

    echo "Creating pod template: ${new_template} (${storage_class})"
    # First, verify the source template has a "viya" volume
    if ! kubectl get podtemplate "${source_template}" -n "${VIYA_NS}" -o json 2>/dev/null | jq -e '.template.spec.volumes[] | select(.name == "viya")' > /dev/null 2>&1; then
        echo "  ERROR: Source pod template does not have a 'viya' volume (required for SASWORK)"
        return 1
    fi
    
    local vol_size="${4:-${PT_VOLUME_SIZE}}"

    # Copy the source pod template and modify it
    kubectl get podtemplate "${source_template}" -n "${VIYA_NS}" -o json | \
    jq --arg new_name "${new_template}" '.metadata.name = $new_name' | \
    jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .metadata.managedFields)' | \
    jq --arg sc "${storage_class}" --arg size "${vol_size}" '(.template.spec.volumes[] | select(.name == "viya")) |= {name: "viya", ephemeral: {volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], storageClassName: $sc, resources: {requests: {storage: $size}}}}}}' \
    > "${output_file}"

    if [[ $? -ne 0 ]]; then
        echo "  ERROR: Failed to create ${output_file}"
        return 1
    fi

    # Verify the storage class is correct
    local sc_check=$(jq -r '.template.spec.volumes[] | select(.name == "viya").ephemeral.volumeClaimTemplate.spec.storageClassName' "${output_file}")
    if [[ "${sc_check}" != "${storage_class}" ]]; then
        echo "  ERROR: storageClassName is '${sc_check}', expected '${storage_class}' in ${output_file}"
        return 1
    fi

    # Apply the new pod template definition to Kubernetes
    kubectl apply -f "${output_file}"
    if [[ $? -eq 0 ]]; then
        echo "  Pod template created successfully"
    else
        echo "  ERROR: Failed to apply pod template"
        return 1
    fi
}

# Function to create pod template with existing PVC
create_podtemplate_pvc() {
    local source_template="$1"
    local new_template="$2"
    local pvc_name="$3"
    local output_file="${WORK_DIR}/definePT_${new_template}.json"

    echo "Creating pod template: ${new_template} (PVC: ${pvc_name})"
    # First, verify the source template has a "viya" volume
    if ! kubectl get podtemplate "${source_template}" -n "${VIYA_NS}" -o json 2>/dev/null | jq -e '.template.spec.volumes[] | select(.name == "viya")' > /dev/null 2>&1; then
        echo "  ERROR: Source pod template does not have a 'viya' volume (required for SASWORK)"
        return 1
    fi
    
    # Verify PVC exists
    if ! kubectl get pvc "${pvc_name}" -n "${VIYA_NS}" &>/dev/null; then
        echo "  ERROR: PVC '${pvc_name}' does not exist in namespace '${VIYA_NS}'"
        return 1
    fi

    kubectl get podtemplate "${source_template}" -n "${VIYA_NS}" -o json | \
    jq --arg new_name "${new_template}" '.metadata.name = $new_name' | \
    jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .metadata.managedFields)' | \
    jq --arg pvc "${pvc_name}" '(.template.spec.volumes[] | select(.name == "viya")) |= {name: "viya", persistentVolumeClaim: {claimName: $pvc}}' \
    > "${output_file}"

    if [[ $? -ne 0 ]]; then
        echo "  ERROR: Failed to create ${output_file}"
        return 1
    fi

    # Verify the viya volume uses PVC
    local vol_check=$(jq -r '.template.spec.volumes[] | select(.name == "viya") | has("persistentVolumeClaim")' "${output_file}")
    if [[ "${vol_check}" != "true" ]]; then
        echo "  ERROR: viya volume is not a PVC in ${output_file}"
        return 1
    fi

    # Apply to Kubernetes
    kubectl apply -f "${output_file}"
    if [[ $? -eq 0 ]]; then
        echo "  Pod template created successfully"
    else
        echo "  ERROR: Failed to apply pod template"
        return 1
    fi
}

# Function to create launcher context
create_launcher_context() {
    local name="$1"
    local description="$2"
    local pod_template="$3"
    local source_context="${4:-SAS Studio launcher context}"
    local template_file="${WORK_DIR}/launcher_context_${name}.json"
    
    echo "Creating launcher context: ${name}"
    echo "  Copying configuration from: ${source_context}"
    
    # Fetch the source launcher context
    sas-viya --output fulljson launcher contexts show --name "${source_context}" > "${template_file}.source" 2>&1
    if [ $? -ne 0 ]; then
        echo "  WARNING: Could not fetch source context '${source_context}', creating basic context with standard allowlist"
        sas-viya launcher contexts create \
            --name "${name}" \
            --launch-type "kubernetes" \
            --description "${description}" \
            --job-pod-template-name "${pod_template}" \
            --command-allowlist "/opt/sas/viya/home/bin/compsrv_start.sh" 2>&1 | tee "${WORK_DIR}/launcher_${pod_template}.log"
        return $?
    fi
    
    # Extract and modify the context, removing server-managed fields
    jq --arg name "${name}" \
       --arg desc "${description}" \
       --arg podtemplate "${pod_template}" \
       'del(.id, .createdBy, .creationTimestamp, .modifiedBy, .modifiedTimestamp, .links, .version) |
        .name = $name |
        .description = $desc |
        .kubernetes |= . + {jobPodTemplateName: $podtemplate}' \
       "${template_file}.source" > "${template_file}"
    
    if [ $? -ne 0 ]; then
        echo "  ERROR: Failed to process context template"
        return 1
    fi
    
    # Extract launch type from the processed JSON
    LAUNCH_TYPE=$(jq -r '.launchType // "kubernetes"' "${template_file}")
    
    if [ -z "$LAUNCH_TYPE" ] || [ "$LAUNCH_TYPE" = "null" ]; then
        echo "  WARNING: Could not determine launch type, defaulting to 'kubernetes'"
        LAUNCH_TYPE="kubernetes"
    fi
    
    echo "  Using launch type: ${LAUNCH_TYPE}"
    
    # Create the new context using JSON file with explicit launch-type
    sas-viya launcher contexts create \
        --name "${name}" \
        --launch-type "${LAUNCH_TYPE}" \
        --json-file "${template_file}" 2>&1 | tee "${WORK_DIR}/launcher_${pod_template}.log"
}

# Function to create batch context
create_batch_context() {
    local name="$1"
    local description="$2"
    local launcher_context_name="$3"
    
    echo "Creating batch context: ${name}"
    
    sas-viya batch contexts create \
        --name "${name}" \
        --description "${description}" \
        --launcher-context-name "${launcher_context_name}" 2>&1 | tee "${WORK_DIR}/batch_context_${name}.log"
}

# Function to create compute context 
create_compute_context() {
    local name="$1"
    local description="$2"
    local launcher_context_name="$3"
    local template_file="${WORK_DIR}/compute_context_${name}.json"

    echo "Creating compute context: ${name}"

    cat << EOF > "${template_file}"
{
    "name": "${name}",
    "description": "${description}",
    "launchContext": {
        "contextName": "${launcher_context_name}"
    },
    "launchType": "service"
}
EOF

    # Create the context
    sas-viya compute contexts create --data @${template_file}
}

#==============================================================================
# Main workflow function
#==============================================================================

main() {
    local VIYA_NS=${VIYA_NS:-"$MY_NS"}

    local PT_VOLUME_SIZE=${PT_VOLUME_SIZE:-"200Gi"}
    local VIYA_URL=$(yq '.configMapGenerator[].literals[] | select(contains("SAS_SERVICES_URL"))' $HOME/project/deploy/$VIYA_NS/kustomization.yaml | cut -d= -f2)

    # Check if namespace exists
    if ! kubectl get namespace "${VIYA_NS}" &>/dev/null; then
        echo -e "\nERROR: Namespace '${VIYA_NS}' does not exist in the cluster"
        echo -e "       \"export MY_NS=your-viya-namespace\" and try again\n"
        return 1
    fi

    # Parse command line arguments
    if [[ $# -ne 4 ]]; then
        echo "Usage: $0 ROOTNAME STORAGE CONTEXT-TYPE CONTEXT-NAME"
        echo "  ROOTNAME: Base name for new resources"
        echo "  STORAGE: 'emptyDir', 'sc:storage-class-name', or 'pvc:pvc-name'"
        echo "  CONTEXT-TYPE: 'compute', 'batch', 'connect', or 'launcher'"
        echo "  CONTEXT-NAME: Name of existing context to clone from"
        return 1
    fi

    local ROOTNAME="$1"
    local STORAGE="$2"
    # Parse STORAGE parameter to determine type and extract value
    local STORAGE_TYPE=""
    local STORAGE_NAME=""

    if [[ "${STORAGE,,}" == "emptydir" ]]; then
        STORAGE_TYPE="emptyDir"
    elif [[ "${STORAGE,,}" =~ ^sc:(.+)$ ]]; then
        STORAGE_TYPE="storageClass"
        STORAGE_NAME="${BASH_REMATCH[1]}"
    elif [[ "${STORAGE,,}" =~ ^pvc:(.+)$ ]]; then
        STORAGE_TYPE="pvc"
        STORAGE_NAME="${BASH_REMATCH[1]}"
    else
        echo -e "\nERROR: Invalid STORAGE format '${STORAGE}'\n"
        echo -e "       Must be 'emptyDir', 'sc:storage-class-name', or 'pvc:pvc-name'\n"
        return 1
    fi
    local CONTEXT_TYPE="$3"
    local CONTEXT_NAME="$4"

    # Configuration
    WORK_DIR="${HOME}/project/deploy/${VIYA_NS}/saswork-providers"
    mkdir -p "${WORK_DIR}"
    echo "Working Directory: ${WORK_DIR}"
    echo "Namespace: ${VIYA_NS}"
    echo

    # Validate context type
    case "${CONTEXT_TYPE}" in
        compute|batch|connect|launcher)
            ;;
        *)
            echo -e "\nERROR: Invalid CONTEXT-TYPE '${CONTEXT_TYPE}'. Must be 'compute', 'batch', 'connect', or 'launcher'\n"
            return 1
            ;;
    esac

    echo "=========================================="
    echo "Creating new SASWORK configuration"
    echo "Root name: ${ROOTNAME}"
    echo "Storage: ${STORAGE}"
    echo "Context type: ${CONTEXT_TYPE}"
    echo "Source context: ${CONTEXT_NAME}"
    echo "=========================================="
    echo

    local LAUNCHER_CONTEXT_NAME
    local PODTEMPLATE_NAME
    local NEW_PODTEMPLATE_NAME="${ROOTNAME}-pt"
    local NEW_LAUNCHER_NAME="${ROOTNAME}-lc"

    case "${CONTEXT_TYPE}" in
        compute|batch)
            # Step 1: Find the SPRE context and get its launcher context
            echo "Step 1: Looking up ${CONTEXT_TYPE} context '${CONTEXT_NAME}'..."
            local CONTEXT_JSON="${WORK_DIR}/source_${CONTEXT_TYPE}_context.json"
            local LAUNCHER_CONTEXT_NAME=""
            local LAUNCHER_CONTEXT_ID=""

            case "${CONTEXT_TYPE}" in
                compute)
                    sas-viya --output fulljson compute contexts show --name "${CONTEXT_NAME}" > "${CONTEXT_JSON}"
                    
                    # Try to get contextName first, then contextId as fallback
                    LAUNCHER_CONTEXT_NAME=$(jq -r '.launchContext.contextName // empty' "${CONTEXT_JSON}")
                    LAUNCHER_CONTEXT_ID=$(jq -r '.launchContext.contextId // empty' "${CONTEXT_JSON}")
                    ;;
                batch)
                    # Batch contexts don't have a 'show' command, need to use list and filter
                    sas-viya --output fulljson batch contexts list --limit 1000 > "${WORK_DIR}/batch_contexts_list.json"
                    jq --arg name "${CONTEXT_NAME}" '.items[] | select(.name == $name)' "${WORK_DIR}/batch_contexts_list.json" > "${CONTEXT_JSON}"
                    
                    # Try to get contextName first, then contextId as fallback
                    LAUNCHER_CONTEXT_NAME=$(jq -r '.launcherContextName // empty' "${CONTEXT_JSON}")
                    LAUNCHER_CONTEXT_ID=$(jq -r '.launcherContextId // empty' "${CONTEXT_JSON}")
                    ;;
            esac

            # If we have the ID but not the name, look up the name
            if [[ -z "${LAUNCHER_CONTEXT_NAME}" ]] && [[ -n "${LAUNCHER_CONTEXT_ID}" ]]; then
                echo "        Found launcher context ID: ${LAUNCHER_CONTEXT_ID}, looking up name..."
                LAUNCHER_CONTEXT_NAME=$(sas-viya --output fulljson launcher contexts show --id "${LAUNCHER_CONTEXT_ID}" | jq -r '.name // empty')
            fi

            # Validate we have a launcher context name
            if [[ -z "${LAUNCHER_CONTEXT_NAME}" ]]; then
                echo -e "\nERROR: Could not find launcher context for ${CONTEXT_TYPE} context '${CONTEXT_NAME}'"
                echo -e "       Checked for: launchContext.contextName, launchContext.contextId, launcherContextName, launcherContextId\n"
                return 1
            fi

            echo "        Found launcher context: ${LAUNCHER_CONTEXT_NAME}"
            echo

            # Step 2: Get the launcher context details to find pod template
            echo "Step 2: Looking up launcher context '${LAUNCHER_CONTEXT_NAME}'..."
            local LAUNCHER_JSON="${WORK_DIR}/source_launcher_context.json"
            sas-viya --output fulljson launcher contexts show --name "${LAUNCHER_CONTEXT_NAME}" > "${LAUNCHER_JSON}"

            PODTEMPLATE_NAME=$(jq -r '.kubernetes.jobPodTemplateName' "${LAUNCHER_JSON}")

            if [[ -z "${PODTEMPLATE_NAME}" ]] || [[ "${PODTEMPLATE_NAME}" == "null" ]]; then
                echo -e "\nERROR: Could not find pod template for launcher context '${LAUNCHER_CONTEXT_NAME}'"
                return 1
            fi

            echo "        Found pod template: ${PODTEMPLATE_NAME}"
            echo

            # Step 3: Create new pod template with modified storage
            echo "Step 3: Creating new pod template..."

            case "${STORAGE_TYPE}" in
                emptyDir)
                    create_podtemplate_emptydir "${PODTEMPLATE_NAME}" "${NEW_PODTEMPLATE_NAME}"
                    ;;
                storageClass)
                    create_podtemplate_sc "${PODTEMPLATE_NAME}" "${NEW_PODTEMPLATE_NAME}" "${STORAGE_NAME}" "${PT_VOLUME_SIZE}"
                    ;;
                pvc)
                    create_podtemplate_pvc "${PODTEMPLATE_NAME}" "${NEW_PODTEMPLATE_NAME}" "${STORAGE_NAME}"
                    ;;
            esac

            if [[ $? -ne 0 ]]; then
                echo -e "\nERROR: Failed to create pod template\n"
                return 1
            fi
            echo

            # Step 4: Create new launcher context
            echo "Step 4: Creating new launcher context..."
            local LAUNCHER_DESC="Launcher context for ${ROOTNAME} (${STORAGE})"

            create_launcher_context "${NEW_LAUNCHER_NAME}" "${LAUNCHER_DESC}" "${NEW_PODTEMPLATE_NAME}" "${LAUNCHER_CONTEXT_NAME}"
            if [[ $? -ne 0 ]]; then
                echo -e "\nERROR: Failed to create launcher context\n"
                return 1
            fi
            echo

            # Step 5: Create new SPRE context
            echo "Step 5: Creating new ${CONTEXT_TYPE} context..."
            local NEW_CONTEXT_NAME

            case "${CONTEXT_TYPE}" in
                compute)
                    NEW_CONTEXT_NAME="${ROOTNAME}-cc"
                    local CONTEXT_DESC="Compute context for ${ROOTNAME} (${STORAGE})"
                    create_compute_context "${NEW_CONTEXT_NAME}" "${CONTEXT_DESC}" "${NEW_LAUNCHER_NAME}"
                    ;;
                batch)
                    NEW_CONTEXT_NAME="${ROOTNAME}-bc"
                    local CONTEXT_DESC="Batch context for ${ROOTNAME} (${STORAGE})"
                    create_batch_context "${NEW_CONTEXT_NAME}" "${CONTEXT_DESC}" "${NEW_LAUNCHER_NAME}"
                    ;;
            esac

            if [[ $? -ne 0 ]]; then
                echo -e "\nERROR: Failed to create ${CONTEXT_TYPE} context\n"
                return 1
            fi

            echo
            echo "=========================================="
            echo "✓ Successfully created new SASWORK configuration"
            echo "  Pod Template: ${NEW_PODTEMPLATE_NAME}"
            echo "  Launcher Context: ${NEW_LAUNCHER_NAME}"
            echo "  ${CONTEXT_TYPE^} Context: ${NEW_CONTEXT_NAME}"
            echo "=========================================="
            ;;

        connect|launcher)
            # For connect/launcher, treat CONTEXT_NAME as launcher context name directly
            LAUNCHER_CONTEXT_NAME="${CONTEXT_NAME}"

            # Step 1: Get the launcher context details to find pod template
            echo "Step 1: Looking up launcher context '${LAUNCHER_CONTEXT_NAME}'..."
            local LAUNCHER_JSON="${WORK_DIR}/source_launcher_context.json"
            sas-viya --output fulljson launcher contexts show --name "${LAUNCHER_CONTEXT_NAME}" > "${LAUNCHER_JSON}"

            PODTEMPLATE_NAME=$(jq -r '.kubernetes.jobPodTemplateName' "${LAUNCHER_JSON}")

            if [[ -z "${PODTEMPLATE_NAME}" ]] || [[ "${PODTEMPLATE_NAME}" == "null" ]]; then
                echo -e "\nERROR: Could not find pod template for launcher context '${LAUNCHER_CONTEXT_NAME}'\n"
                return 1
            fi

            echo "        Found pod template: ${PODTEMPLATE_NAME}"
            echo

            # Step 2: Create new pod template with modified storage
            echo "Step 2: Creating new pod template..."

            case "${STORAGE_TYPE}" in
                emptyDir)
                    create_podtemplate_emptydir "${PODTEMPLATE_NAME}" "${NEW_PODTEMPLATE_NAME}"
                    ;;
                storageClass)
                    create_podtemplate_sc "${PODTEMPLATE_NAME}" "${NEW_PODTEMPLATE_NAME}" "${STORAGE_NAME}" "${PT_VOLUME_SIZE}"
                    ;;
                pvc)
                    create_podtemplate_pvc "${PODTEMPLATE_NAME}" "${NEW_PODTEMPLATE_NAME}" "${STORAGE_NAME}"
                    ;;
            esac

            if [[ $? -ne 0 ]]; then
                echo -e "\nERROR: Failed to create pod template\n"
                return 1
            fi
            echo

            # Step 3: Create new launcher context
            echo "Step 3: Creating new launcher context..."
            local LAUNCHER_DESC="Launcher context for ${ROOTNAME} (${STORAGE})"

            create_launcher_context "${NEW_LAUNCHER_NAME}" "${LAUNCHER_DESC}" "${NEW_PODTEMPLATE_NAME}" "${CONTEXT_NAME}"
            if [[ $? -ne 0 ]]; then
                echo -e "\nERROR: Failed to create launcher context\n"
                return 1
            fi

            echo
            echo "=========================================="
            echo "✓ Successfully created new SASWORK configuration"
            echo "  Pod Template: ${NEW_PODTEMPLATE_NAME}"
            echo "  Launcher Context: ${NEW_LAUNCHER_NAME}"
            echo "=========================================="

            # Special instructions for connect context
            if [[ "${CONTEXT_TYPE}" == "connect" ]]; then
                local STORAGE_DESC
                if [[ "${STORAGE}" == "emptyDir" ]]; then
                    STORAGE_DESC="emptyDir"
                else
                    STORAGE_DESC="${STORAGE}"
                fi

                echo
                echo "=========================================================="
                echo "NEXT STEPS: Create Connect Context via Environment Manager"
                echo "=========================================================="
                echo
                echo "Connect contexts must be created through the SAS Environment Manager UI:"
                echo
                echo "1. Open SAS Viya Environment Manager"
                echo "   - URL: ${VIYA_URL}/SASEnvironmentManager"
                echo "   - Navigate to: Contexts (left menu)"
                echo "   - View: Select 'Connect contexts' (pull-down menu)"
                echo
                echo "2. Duplicate the source connect context"
                echo "   - Select 'default-launcher' from the list"
                echo "   - Click the Copy button (two pages icon)"
                echo
                echo "3. Fill in the prompts:"
                echo "   - Name: ${ROOTNAME}-cc"
                echo "   - Description: Connect context for ${ROOTNAME} (${STORAGE_DESC})"
                echo "   - Sign-on type: Launcher"
                echo "   - Launcher context: ${NEW_LAUNCHER_NAME}"
                echo
                echo "4. Save."
                echo
                echo "=========================================="
            fi
            ;;
    esac
}

#==============================================================================
# Script execution
#==============================================================================

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi