#!/bin/bash

# Zscaler Client Connector Deployment Script
# This script orchestrates the deployment of Zscaler across Linux and macOS endpoints

set -e

# Configuration
PLAYBOOK_DIR="."
INVENTORY_FILE="$PLAYBOOK_DIR/inventory/hosts"
VAULT_PASSWORD_FILE="$PLAYBOOK_DIR/.vault_pass"
LOG_DIR="$PLAYBOOK_DIR/logs/zscaler-deployment"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v ansible &> /dev/null; then
        error "Ansible is not installed. Please install Ansible first."
        exit 1
    fi
    
    if ! command -v ansible-vault &> /dev/null; then
        error "Ansible Vault is not available."
        exit 1
    fi
    
    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        error "Vault password file not found: $VAULT_PASSWORD_FILE"
        exit 1
    fi
    
    if [ ! -f "$INVENTORY_FILE" ]; then
        error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Test connectivity to target hosts
test_connectivity() {
    log "Testing connectivity to target hosts..."
    
    if ansible all -i "$INVENTORY_FILE" -m ping --vault-password-file "$VAULT_PASSWORD_FILE"; then
        success "All hosts are reachable"
    else
        warning "Some hosts may not be reachable. Check the log for details."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Deploy to Linux systems
deploy_linux() {
    log "Starting Linux deployment..."
    
    if ansible-playbook -i "$INVENTORY_FILE" \
        --vault-password-file "$VAULT_PASSWORD_FILE" \
        --limit linux_clients \
        "$PLAYBOOK_DIR/zscaler-linux.yml" \
        --extra-vars "deployment_timestamp=$(date +%s)" \
        | tee -a "$LOG_FILE"; then
        success "Linux deployment completed successfully"
        return 0
    else
        error "Linux deployment failed"
        return 1
    fi
}

# Deploy to macOS systems
deploy_macos() {
    log "Starting macOS deployment..."
    
    if ansible-playbook -i "$INVENTORY_FILE" \
        --vault-password-file "$VAULT_PASSWORD_FILE" \
        --limit macos_clients \
        "$PLAYBOOK_DIR/zscaler-macos.yml" \
        --extra-vars "deployment_timestamp=$(date +%s)" \
        | tee -a "$LOG_FILE"; then
        success "macOS deployment completed successfully"
        return 0
    else
        error "macOS deployment failed"
        return 1
    fi
}

# Generate deployment report
generate_report() {
    log "Generating deployment report..."
    
    REPORT_FILE="$LOG_DIR/deployment-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
Zscaler Client Connector Deployment Report
==========================================
Date: $(date)
Log File: $LOG_FILE

Host Status Summary:
EOF
    
    # Check Zscaler service status on all hosts
    ansible all -i "$INVENTORY_FILE" \
        --vault-password-file "$VAULT_PASSWORD_FILE" \
        -m shell -a "systemctl is-active zscaler 2>/dev/null || launchctl list | grep zscaler" \
        --one-line >> "$REPORT_FILE" 2>/dev/null || true
    
    log "Report generated: $REPORT_FILE"
}

# Rollback function (basic)
rollback() {
    log "Starting rollback procedure..."
    
    # Stop services
    log "Attempting to stop Zscaler services on all hosts..."
    ansible all -i "$INVENTORY_FILE" \
        --vault-password-file "$VAULT_PASSWORD_FILE" \
        -m shell -a "systemctl stop zscaler 2>/dev/null || launchctl unload -w /Library/LaunchDaemons/com.zscaler.client.connector.plist 2>/dev/null || echo 'Stop command completed'" \
        | tee -a "$LOG_FILE" || true
    
    warning "Rollback completed. Manual cleanup may be required."
}

# Main execution
main() {
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    log "Starting Zscaler deployment process"
    log "Log file: $LOG_FILE"
    
    # Handle script arguments
    case "${1:-}" in
        "linux")
            check_prerequisites
            test_connectivity
            deploy_linux
            ;;
        "macos")
            check_prerequisites
            test_connectivity
            deploy_macos
            ;;
        "all")
            check_prerequisites
            test_connectivity
            LINUX_RESULT=0
            MACOS_RESULT=0
            
            deploy_linux || LINUX_RESULT=$?
            deploy_macos || MACOS_RESULT=$?
            
            if [ $LINUX_RESULT -eq 0 ] && [ $MACOS_RESULT -eq 0 ]; then
                success "All deployments completed successfully"
            else
                error "Some deployments failed. Check logs for details."
            fi
            ;;
        "rollback")
            rollback
            ;;
        "test")
            check_prerequisites
            test_connectivity
            ;;
        "report")
            generate_report
            ;;
        *)
            echo "Usage: $0 {linux|macos|all|rollback|test|report}"
            echo "  linux   - Deploy to Linux systems only"
            echo "  macos   - Deploy to macOS systems only"  
            echo "  all     - Deploy to all systems"
            echo "  rollback - Stop Zscaler services on all systems"
            echo "  test    - Test connectivity to all hosts"
            echo "  report  - Generate status report"
            exit 1
            ;;
    esac
    
    generate_report
    log "Deployment process completed"
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"