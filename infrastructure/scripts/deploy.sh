#!/bin/bash
set -e

# Onestack Infrastructure Deployment Script
# Usage: ./deploy.sh [command] [options]

# Fix locale for Ansible on macOS
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"
VAULT_PASSWORD_FILE="$HOME/.ansible-vault-password"

cd "$ANSIBLE_DIR"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_vault_password() {
    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        log_error "Vault password file not found at $VAULT_PASSWORD_FILE"
        log_info "Create it with: echo 'your-vault-password' > $VAULT_PASSWORD_FILE && chmod 600 $VAULT_PASSWORD_FILE"
        exit 1
    fi
}

run_playbook() {
    local playbook=$1
    shift
    check_vault_password
    log_info "Running playbook: $playbook"
    ansible-playbook "playbooks/$playbook" --vault-password-file "$VAULT_PASSWORD_FILE" "$@"
}

case "${1:-help}" in
    setup)
        log_info "Running initial server setup..."
        run_playbook setup.yml "${@:2}"
        ;;

    all)
        log_info "Deploying complete infrastructure..."
        run_playbook site.yml "${@:2}"
        ;;

    traefik)
        log_info "Deploying Traefik..."
        run_playbook deploy-traefik.yml "${@:2}"
        ;;

    databases)
        log_info "Deploying databases..."
        run_playbook deploy-databases.yml "${@:2}"
        ;;

    apps)
        log_info "Deploying all applications..."
        run_playbook deploy-apps.yml "${@:2}"
        ;;

    app)
        if [ -z "$2" ]; then
            log_error "Please specify an app name: ./deploy.sh app allbids"
            exit 1
        fi
        log_info "Deploying $2..."
        run_playbook deploy-apps.yml -e "deploy_app=$2" "${@:3}"
        ;;

    backup)
        log_info "Running backup..."
        run_playbook backup.yml "${@:2}"
        ;;

    encrypt)
        log_info "Encrypting vault file..."
        check_vault_password
        ansible-vault encrypt inventory/group_vars/all/vault.yml --vault-password-file "$VAULT_PASSWORD_FILE"
        ;;

    decrypt)
        log_info "Decrypting vault file..."
        check_vault_password
        ansible-vault decrypt inventory/group_vars/all/vault.yml --vault-password-file "$VAULT_PASSWORD_FILE"
        ;;

    edit-vault)
        log_info "Editing vault file..."
        check_vault_password
        ansible-vault edit inventory/group_vars/all/vault.yml --vault-password-file "$VAULT_PASSWORD_FILE"
        ;;

    ping)
        log_info "Testing connectivity..."
        ansible all -m ping
        ;;

    help|*)
        echo "Onestack Infrastructure Deployment"
        echo ""
        echo "Usage: ./deploy.sh [command] [options]"
        echo ""
        echo "Commands:"
        echo "  setup       - Initial server setup (common packages, Docker)"
        echo "  all         - Deploy complete infrastructure"
        echo "  traefik     - Deploy/update Traefik only"
        echo "  databases   - Deploy/update databases only"
        echo "  apps        - Deploy/update all applications"
        echo "  app <name>  - Deploy/update specific app (e.g., ./deploy.sh app allbids)"
        echo "  backup      - Run backup playbook"
        echo "  encrypt     - Encrypt vault.yml"
        echo "  decrypt     - Decrypt vault.yml"
        echo "  edit-vault  - Edit encrypted vault.yml"
        echo "  ping        - Test connectivity to all hosts"
        echo ""
        echo "Options (passed to ansible-playbook):"
        echo "  --check     - Dry run, don't make changes"
        echo "  --diff      - Show differences"
        echo "  -v/-vv/-vvv - Increase verbosity"
        echo ""
        echo "Examples:"
        echo "  ./deploy.sh all --check    # Dry run full deployment"
        echo "  ./deploy.sh app allbids    # Deploy AllBids only"
        echo "  ./deploy.sh backup         # Run backup"
        ;;
esac
