#!/usr/bin/env bash
set -euo pipefail

# 1) guard: ensure we're in the right folder
if [[ "$(basename "$PWD")" != "onestack_products" ]]; then
  echo "⛔️  ERROR: you must run this from the directory named onestack_products"
  exit 1
fi

# 2) tweak these for your environment
SSH_USER="your_user"
SSH_HOST="your.host.tld"
SSH_KEY="/path/to/your/id_rsa"   # optional, if you need a specific key
REMOTE_PATH="/root"

# 3) rsync command
rsync -avz --delete \
  -e "ssh -i ${SSH_KEY}" \
  ./ \
  ${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}/

echo "✅ Synced to ${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}"