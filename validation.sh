#!/bin/bash

# Zscaler Deployment Setup and Validation Script
# This script helps validate and set up the deployment environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_DIR="/opt/zscaler-deployment"
REQUIRED_FILES=(
    "deploy-zscaler.sh"
    "zscaler-linux.yml"
    "zscaler-macos.yml"
    "zscaler-advanced-protection.yml"
    "inventory/hosts"
    "group_vars/all/vault.yml"
    ".vault_pass"
)

print_header() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "Zscaler Deployment Setup & Validation"
    echo "=================================================="
    echo -e "${NC}"
}

print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "ok")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "warn")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "error")
            echo -e "${RED}✗${NC} $message"
            ;;
        "info")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
    esac
}

check_prerequisites() {
    print_status "info" "Checking prerequisites..."
    
    # Check if running as root for setup
    if [[ $EUID -eq 0 ]]; then
        print_status "warn" "Running as root. Consider running as a regular user with sudo access."
    fi
    
    # Check Ansible installation
    if command -v ansible >/dev/null 2>&1; then
        local ansible_version=$(ansible --version | head -n1 | awk '{print $2}')
        print_status "ok" "Ansible installed: $ansible_version"
    else
        print_status "error" "Ansible not found. Install with: pip3 install ansible"
        return 1
    fi
    
    # Check ansible-vault
    if command -v ansible-vault >/dev/null 2>&1; then
        print_status "ok" "ansible-vault available"
    else
        print_status "error" "ansible-vault not found"
        return 1
    fi
    
    # Check Python
    if command -v python3 >/dev/null 2>&1; then
        local python_version=$(python3 --version | awk '{print $2}')
        print_status "ok" "Python3 installed: $python_version"
    else
        print_status "error" "Python3 not found"
        return 1
    fi
    
    # Check SSH
    if command -v ssh >/dev/null 2>&1; then
        print_status "ok" "SSH client available"
    else
        print_status "error" "SSH client not found"
        return 1
    fi
    
    return 0
}

validate_file_syntax() {
    print_status "info" "Validating script syntax..."
    
    # Check main deployment script
    if [[ -f "deploy-zscaler.sh" ]]; then
        if bash -n deploy-zscaler.sh; then
            print_status "ok" "deploy-zscaler.sh syntax valid"
        else
            print_status "error" "deploy-zscaler.sh has syntax errors"
            return 1
        fi
    else
        print_status "error" "deploy-zscaler.sh not found"
        return 1
    fi
    
    # Check YAML syntax for playbooks
    local yaml_files=("zscaler-linux.yml" "zscaler-macos.yml" "zscaler-advanced-protection.yml")
    for file in "${yaml_files[@]}"; do
        if [[ -f "$file" ]]; then
            if ansible-playbook --syntax-check "$file" >/dev/null 2>&1; then
                print_status "ok" "$file syntax valid"
            else
                print_status "error" "$file has YAML syntax errors"
                return 1
            fi
        else
            print_status "warn" "$file not found (optional)"
        fi
    done
    
    return 0
}

check_file_structure() {
    print_status "info" "Checking file structure..."
    
    local missing_files=()
    local optional_files=("zscaler-advanced-protection.yml")
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ -f "$file" ]] || [[ -d "$file" ]]; then
            print_status "ok" "$file exists"
        else
            # Check if it's optional
            local is_optional=false
            for opt_file in "${optional_files[@]}"; do
                if [[ "$file" == *"$opt_file"* ]]; then
                    is_optional=true
                    break
                fi
            done
            
            if [[ "$is_optional" == "true" ]]; then
                print_status "warn" "$file missing (optional)"
            else
                print_status "error" "$file missing (required)"
                missing_files+=("$file")
            fi
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_status "error" "Missing required files: ${missing_files[*]}"
        return 1
    fi
    
    return 0
}

validate_inventory() {
    print_status "info" "Validating inventory configuration..."
    
    if [[ -f "inventory/hosts" ]]; then
        # Check if inventory has at least one host
        if ansible-inventory -i inventory/hosts --list --vault-password-file .vault_pass    >/dev/null 2>&1; then
            local host_count=$(ansible-inventory -i inventory/hosts --list --vault-password-file .vault_pass    | jq '.["_meta"]["hostvars"] | length' 2>/dev/null || echo "0")
            if [[ "$host_count" -gt 0 ]]; then
                print_status "ok" "Inventory valid with $host_count hosts"
            else
                print_status "warn" "Inventory appears empty"
            fi
        else
            print_status "error" "Inventory syntax error"
            return 1
        fi
    else
        print_status "error" "Inventory file not found"
        return 1
    fi
    
    return 0
}

validate_vault() {
    print_status "info" "Validating vault configuration..."
    
    if [[ -f ".vault_pass" ]]; then
        local perms=$(stat -c %a .vault_pass 2>/dev/null || stat -f %Mp%Lp .vault_pass 2>/dev/null || echo "unknown")
        if [[ "$perms" == "0600" ]]; then
            print_status "ok" "Vault password file permissions correct"
        else
            print_status "warn" "Vault password file should have 600 permissions"
            chmod 600 .vault_pass
            print_status "ok" "Fixed vault password file permissions"
        fi
    else
        print_status "error" "Vault password file not found"
        return 1
    fi
    
    if [[ -f "group_vars/all/vault.yml" ]]; then
        if ansible-vault view group_vars/all/vault.yml --vault-password-file .vault_pass >/dev/null 2>&1; then
            print_status "ok" "Vault file can be decrypted"
        else
            print_status "error" "Cannot decrypt vault file - check password"
            return 1
        fi
    else
        print_status "error" "Vault variables file not found"
        return 1
    fi
    
    return 0
}

create_directory_structure() {
    print_status "info" "Creating directory structure..."
    
    local directories=(
        "inventory"
        "group_vars/all"
        "logs"
        "playbooks"
        "scripts"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_status "ok" "Created directory: $dir"
        else
            print_status "ok" "Directory exists: $dir"
        fi
    done
}

setup_example_configs() {
    print_status "info" "Setting up example configurations..."
    
    # Create example inventory if it doesn't exist
    if [[ ! -f "inventory/hosts" ]]; then
        cat > inventory/hosts << 'EOF'
[linux_clients]
# Add your Linux systems here
# example-linux ansible_host=192.168.1.100 ansible_user=admin

[macos_clients] 
# Add your macOS systems here
# example-mac ansible_host=192.168.1.200 ansible_user=admin

[linux_clients:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become=yes
ansible_become_method=sudo

[macos_clients:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become=yes
ansible_become_method=sudo

[all:vars]
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
        print_status "ok" "Created example inventory file"
    fi
    
    # Create example vault password file
    if [[ ! -f ".vault_pass" ]]; then
        echo "change-this-vault-password" > .vault_pass
        chmod 600 .vault_pass
        print_status "warn" "Created example vault password file - CHANGE THE PASSWORD!"
    fi
    
    # Create example vault variables if they don't exist
    if [[ ! -f "group_vars/all/vault.yml" ]]; then
        cat > /tmp/vault_template.yml << 'EOF'
# Zscaler Configuration Variables
vault_zscaler_root_cert_url: "https://your-zscaler-instance.zscalerbeta.net/auth/cert"
vault_zscaler_user_domain: "company.domain.com"
vault_monitoring_email: "admin@company.com"
vault_slack_webhook: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

vault_zscaler_app_profile: |
  <?xml version="1.0" encoding="UTF-8"?>
  <AppProfile>
    <ServerName>your-zscaler-cloud.zscalerbeta.net</ServerName>
    <AppServerName>your-zscaler-cloud.zscalerbeta.net</AppServerName>
    <UserDomain>company.domain.com</UserDomain>
    <HideAppUI>true</HideAppUI>
    <DisableUninstall>true</DisableUninstall>
    <AutoConnect>true</AutoConnect>
    <PolicyToken>your-policy-token-here</PolicyToken>
  </AppProfile>

vault_zscaler_policy_token: "your-policy-token-here"
EOF
        
        ansible-vault encrypt /tmp/vault_template.yml --vault-password-file .vault_pass --output group_vars/all/vault.yml
        rm /tmp/vault_template.yml
        print_status "ok" "Created encrypted vault variables file"
        print_status "warn" "Edit group_vars/all/vault.yml with your Zscaler configuration"
    fi
}

run_connectivity_test() {
    print_status "info" "Testing connectivity to target hosts..."
    
    if ansible all -i inventory/hosts -m ping --vault-password-file .vault_pass >/dev/null 2>&1; then
        print_status "ok" "All hosts are reachable"
        return 0
    else
        print_status "warn" "Some hosts may not be reachable"
        print_status "info" "Run 'ansible all -i inventory/hosts -m ping --vault-password-file .vault_pass' for details"
        return 1
    fi
}

display_next_steps() {
    echo ""
    print_status "info" "Next Steps:"
    echo "  1. Edit inventory/hosts with your target systems"
    echo "  2. Edit group_vars/all/vault.yml with your Zscaler configuration:"
    echo "     ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass"
    echo "  3. Test connectivity: ./deploy-zscaler.sh test"
    echo "  4. Deploy: ./deploy-zscaler.sh all"
    echo ""
    print_status "info" "For help: ./deploy-zscaler.sh"
}

main() {
    print_header
    
    local exit_code=0
    
    # Run all checks
    check_prerequisites || exit_code=1
    create_directory_structure
    setup_example_configs
    check_file_structure || exit_code=1
    validate_file_syntax || exit_code=1
    validate_inventory || exit_code=1
    validate_vault || exit_code=1
    
    if [[ "$exit_code" -eq 0 ]]; then
        run_connectivity_test || true  # Don't fail on connectivity issues
        
        echo ""
        print_status "ok" "Setup validation completed successfully!"
        display_next_steps
    else
        echo ""
        print_status "error" "Setup validation failed. Please fix the issues above."
    fi
    
    return $exit_code
}

# Handle script arguments
case "${1:-setup}" in
    "setup"|"validate")
        main
        ;;
    "syntax")
        validate_file_syntax
        ;;
    "connectivity")
        run_connectivity_test
        ;;
    *)
        echo "Usage: $0 [setup|validate|syntax|connectivity]"
        echo "  setup        - Run full setup and validation (default)"
        echo "  validate     - Same as setup"
        echo "  syntax       - Check script syntax only"
        echo "  connectivity - Test host connectivity only"
        exit 1
        ;;
esac