#!/bin/bash
set -e

# New Server Setup Script
# Usage: ./new-server.sh <server-ip> [ssh-user]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"

if [ -z "$1" ]; then
    echo "Usage: ./new-server.sh <server-ip> [ssh-user]"
    echo ""
    echo "This script helps set up a new server for deployment."
    exit 1
fi

SERVER_IP="$1"
SSH_USER="${2:-root}"

echo "======================================"
echo "New Server Setup for $SERVER_IP"
echo "======================================"

# Test SSH connectivity
echo "Testing SSH connectivity..."
if ! ssh -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'"; then
    echo "ERROR: Cannot connect to $SERVER_IP"
    echo "Make sure:"
    echo "  1. The server is running"
    echo "  2. SSH is enabled"
    echo "  3. Your SSH key is added to the server"
    exit 1
fi

# Install Python if needed (required for Ansible)
echo "Checking Python installation..."
ssh "$SSH_USER@$SERVER_IP" "which python3 || apt-get update && apt-get install -y python3"

# Update inventory
echo ""
echo "======================================"
echo "Update your inventory file:"
echo "======================================"
echo ""
echo "Edit: $ANSIBLE_DIR/inventory/hosts.yml"
echo ""
echo "Add or update:"
echo "---"
echo "all:"
echo "  children:"
echo "    production:"
echo "      hosts:"
echo "        new-server:  # rename as needed"
echo "          ansible_host: $SERVER_IP"
echo "          ansible_user: $SSH_USER"
echo ""

# Remind about vault
echo "======================================"
echo "Update vault with secrets:"
echo "======================================"
echo ""
echo "Run: cd $ANSIBLE_DIR && ./scripts/deploy.sh edit-vault"
echo ""
echo "Make sure to set all required secrets!"
echo ""

# Test ansible connectivity
echo "======================================"
echo "Test Ansible Connectivity"
echo "======================================"
echo ""
echo "Run: cd $ANSIBLE_DIR && ansible all -m ping"
echo ""

echo "======================================"
echo "Deploy to the new server"
echo "======================================"
echo ""
echo "Initial setup:  ./scripts/deploy.sh setup"
echo "Full deploy:    ./scripts/deploy.sh all"
echo ""
