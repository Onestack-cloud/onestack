#!/bin/bash
set -e

# Quick backup script - can be run via cron
# Usage: ./backup.sh [remote-destination]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"
VAULT_PASSWORD_FILE="$HOME/.ansible-vault-password"

cd "$ANSIBLE_DIR"

# Run the backup playbook
ansible-playbook playbooks/backup.yml --vault-password-file "$VAULT_PASSWORD_FILE"

# Optionally sync to remote storage
if [ -n "$1" ]; then
    echo "Syncing backups to $1..."
    rsync -avz --delete "root@${SSH_HOST:-YOUR_SERVER_IP}:/root/backups/" "$1"
fi

echo "Backup completed successfully!"
