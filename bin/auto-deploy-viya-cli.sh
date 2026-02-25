#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# =============================================================================
# SAS Viya CLI and Pyviyatools Setup Script
# =============================================================================
# This script automates the complete setup of:
# 1. pyviyatools (Python tools for SAS Viya REST API)
# 2. sas-viya CLI with all plugins
# 3. SSL certificate configuration from Kubernetes Viya namespace
# 
# Usage: ./auto-deploy-viya-cli.sh [OPTIONS]
# Options:
#   -n, --namespace <name>    Specify Viya namespace (default: viya)
#   -h, --help               Show this help message
# =============================================================================

set -e  # Exit on any error

# Default values
VIYA_NAMESPACE="viya"
GELLOW_SCRIPTS_DIR="/opt/gellow_code/scripts/loop/viya4"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOH
SAS Viya Pyviyatools and CLI Setup Script

This script automates the complete setup of pyviyatools and sas-viya CLI
with proper SSL certificate configuration for SAS Viya environments.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -n, --namespace <name>    Specify Viya namespace (default: viya)
    -h, --help               Show this help message

EXAMPLES:
    $0                       # Use default namespace 'viya'
    $0 -n my-viya            # Use custom namespace 'my-viya'

REQUIREMENTS:
    - kubectl access to Kubernetes cluster with SAS Viya deployed
    - GELLOW scripts available at /opt/gellow_code/scripts/
    - Internet connectivity for downloading packages
    - sudo privileges for system-level installations

EOH
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            VIYA_NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution function
main() {
    log_info "Starting SAS Viya Pyviyatools and CLI Setup"
    log_info "Target namespace: $VIYA_NAMESPACE"
    echo
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl get namespace "$VIYA_NAMESPACE" &> /dev/null; then
        log_error "Namespace '$VIYA_NAMESPACE' does not exist"
        exit 1
    fi
    
    if [[ ! -d "$GELLOW_SCRIPTS_DIR" ]]; then
        log_error "GELLOW scripts directory not found: $GELLOW_SCRIPTS_DIR"
        exit 1
    fi
    
    log_success "Prerequisites met"
    echo
    
    # Install pyviyatools
    log_info "Installing pyviyatools..."
    if sudo "$GELLOW_SCRIPTS_DIR/GEL.0311.Optional.Install.pyviyatools.sh" pyviyatools-install; then
        log_success "Pyviyatools installation completed"
    else
        log_error "Pyviyatools installation failed"
        exit 1
    fi
    echo
    
    # Install SAS CLI
    log_info "Installing SAS Viya CLI..."
    if sudo "$GELLOW_SCRIPTS_DIR/GEL.0302.Optional.Install.sas-viya-cli.sh" sas-viya-install; then
        log_success "SAS Viya CLI installation completed"
    else
        log_error "SAS Viya CLI installation failed"
        exit 1
    fi
    echo
    
    # Configure SSL certificates with wrapper approach
    log_info "Configuring SSL certificates from namespace '$VIYA_NAMESPACE'..."
    
    cert_secrets=("sas-viya-ca-certificate-secret" "sas-ingress-certificate")
    found_cert=""
    
    for secret in "${cert_secrets[@]}"; do
        if kubectl get secret "$secret" -n "$VIYA_NAMESPACE" &> /dev/null; then
            found_cert="$secret"
            break
        fi
    done
    
    if [[ -n "$found_cert" ]]; then
        mkdir -p "$HOME/.certs"
        kubectl get secret "$found_cert" -n "$VIYA_NAMESPACE" -o jsonpath='{.data.ca\.crt}' | base64 -d > "$HOME/.certs/sas-viya-ca.crt"
        
        # Remove any existing global SSL cert exports from .bashrc
        #sed -i '/SSL_CERT_FILE.*sas-viya-ca.crt/d' "$HOME/.bashrc" 2>/dev/null || true
        #sed -i '/REQUESTS_CA_BUNDLE.*sas-viya-ca.crt/d' "$HOME/.bashrc" 2>/dev/null || true
        
        # Create ~/bin directory and wrapper scripts
        mkdir -p "$HOME/bin"
        
        # Find the actual sas-viya binary location
        SASVIYA_BINARY=$(which sas-viya 2>/dev/null || echo "/usr/bin/sas-viya")
        if [[ "$SASVIYA_BINARY" == "$HOME/bin/sas-viya" ]]; then
            # Already using wrapper, find the real binary
            SASVIYA_BINARY="/usr/bin/sas-viya"
        fi
        
        # Create sas-viya wrapper
        cat > "$HOME/bin/sas-viya" << WRAPPER_EOF
#!/bin/bash
# Wrapper script for sas-viya CLI with isolated SSL cert environment variables

# Set SSL cert variables only for this execution
export SSL_CERT_FILE="$HOME/.certs/sas-viya-ca.crt"
export REQUESTS_CA_BUNDLE="$HOME/.certs/sas-viya-ca.crt"

# Execute the real sas-viya command with all arguments
exec $SASVIYA_BINARY "\$@"
WRAPPER_EOF
        
        chmod +x "$HOME/bin/sas-viya"
        
        # Create pyviyatools wrapper for easier SSL certificate handling
        cat > "$HOME/bin/pyviyatools" << PYVIYA_EOF
#!/bin/bash
# Wrapper script for pyviyatools with isolated SSL cert environment variables

# Set SSL cert variables only for this execution
export SSL_CERT_FILE="$HOME/.certs/sas-viya-ca.crt"
export REQUESTS_CA_BUNDLE="$HOME/.certs/sas-viya-ca.crt"

# Change to pyviyatools directory and execute the Python script
cd /opt/pyviyatools
exec python3 "\$@"
PYVIYA_EOF
        
        chmod +x "$HOME/bin/pyviyatools"
        
        # Ensure ~/bin is in PATH
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"; then
            echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        
        # Also update pyviyatools configuration
        PYVIYA_CONFIG="$HOME/.pyviyatools_config"
        if [[ -f "$PYVIYA_CONFIG" ]]; then
            # Update existing config to use wrapper approach for SSL certs
            sed -i '/SSL_CERT_FILE/d' "$PYVIYA_CONFIG" 2>/dev/null || true
            sed -i '/REQUESTS_CA_BUNDLE/d' "$PYVIYA_CONFIG" 2>/dev/null || true
            echo "# SSL certificates handled by wrapper scripts" >> "$PYVIYA_CONFIG"
        fi
        
        log_success "SSL certificates configured with isolated wrapper approach for both sas-viya and pyviyatools"
        log_info "SSL environment variables will only be active when using sas-viya or pyviyatools wrappers"
    else
        log_warning "No SSL certificate found, skipping SSL configuration"
    fi
    echo
    
    log_success "=== The sas-viya CLI and pyviyatools are installed ==="
    log_info ""
    log_info "NOTE: Wrapper scripts provided to isolate SSL configuration"
    log_info " Use: ~/bin/sas-viya    ==> /usr/bin/sas-viya (with its SSL certs)"
    log_info " Use: ~/bin/pyviyatools ==> /opt/pyviyatools  (with its SSL certs)"
    log_info ""
    log_info "Next steps:"
    log_info "1. Source environment: source ~/.bashrc"
    log_info "2. Create profile: sas-viya profile init"
    log_info "3. Login: sas-viya auth login"
    log_info "4. Test pyviyatools: pyviyatools showsetup.py"
}

# Run main function
main "$@"