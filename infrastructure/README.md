# Onestack infrastructure

Infrastructure as Code (IaC) for deploying and managing Onestack services using Ansible.

## Overview

This repository contains Ansible playbooks and roles to:
- Set up new servers with all required dependencies
- Deploy and manage Traefik reverse proxy
- Deploy shared databases (PostgreSQL, MariaDB, MongoDB, Valkey Redis)
- Deploy applications (AllBids, n8n, Kimai, etc.)
- Configure monitoring with Netdata
- Manage backups

## Prerequisites

1. **Ansible installed locally**:
   ```bash
   # macOS
   brew install ansible

   # Ubuntu/Debian
   sudo apt install ansible
   ```

2. **SSH access to target servers** (key-based authentication recommended)

3. **Vault password file** for secrets:
   ```bash
   echo 'your-secure-vault-password' > ~/.ansible-vault-password
   chmod 600 ~/.ansible-vault-password
   ```

## Quick start

### 1. Configure secrets

Edit the vault file to add your actual secrets:

```bash
cd infrastructure/ansible
ansible-vault edit inventory/group_vars/all/vault.yml --vault-password-file ~/.ansible-vault-password
```

Replace all `REPLACE_WITH_ACTUAL_*` placeholders with real values.

### 2. Update inventory

Edit `ansible/inventory/hosts.yml` to add your servers:

```yaml
all:
  children:
    production:
      hosts:
        my-server:
          ansible_host: 1.2.3.4
          ansible_user: root
```

### 3. Test connectivity

```bash
cd infrastructure
./scripts/deploy.sh ping
```

### 4. Deploy

```bash
# Initial server setup (Docker, firewall, etc.)
./scripts/deploy.sh setup

# Full deployment
./scripts/deploy.sh all

# Or deploy specific components
./scripts/deploy.sh traefik
./scripts/deploy.sh databases
./scripts/deploy.sh app allbids
```

## Directory structure

```
infrastructure/
├── ansible/
│   ├── ansible.cfg              # Ansible configuration
│   ├── inventory/
│   │   ├── hosts.yml            # Server inventory
│   │   └── group_vars/
│   │       └── all/
│   │           ├── vars.yml     # Shared variables
│   │           └── vault.yml    # Encrypted secrets
│   ├── playbooks/
│   │   ├── site.yml             # Full deployment
│   │   ├── setup.yml            # Initial server setup
│   │   ├── deploy-apps.yml      # Deploy applications
│   │   ├── deploy-traefik.yml   # Deploy Traefik
│   │   ├── deploy-databases.yml # Deploy databases
│   │   └── backup.yml           # Backup playbook
│   └── roles/
│       ├── common/              # Base server packages, firewall
│       ├── docker/              # Docker installation
│       ├── traefik/             # Traefik reverse proxy
│       ├── databases/           # PostgreSQL, MariaDB, MongoDB, Valkey
│       ├── apps/                # Application deployments
│       └── netdata/             # Monitoring
└── scripts/
    ├── deploy.sh                # Main deployment script
    ├── backup.sh                # Backup script
    └── new-server.sh            # New server setup helper
```

## Available commands

| Command | Description |
|---------|-------------|
| `./scripts/deploy.sh setup` | Initial server setup (packages, Docker, firewall) |
| `./scripts/deploy.sh all` | Deploy complete infrastructure |
| `./scripts/deploy.sh traefik` | Deploy/update Traefik |
| `./scripts/deploy.sh databases` | Deploy/update databases |
| `./scripts/deploy.sh apps` | Deploy/update all applications |
| `./scripts/deploy.sh app <name>` | Deploy specific app (e.g., `allbids`, `n8n`) |
| `./scripts/deploy.sh backup` | Run backup playbook |
| `./scripts/deploy.sh encrypt` | Encrypt vault.yml |
| `./scripts/deploy.sh decrypt` | Decrypt vault.yml |
| `./scripts/deploy.sh edit-vault` | Edit encrypted vault |
| `./scripts/deploy.sh ping` | Test connectivity |

## Adding a new application

1. Create task file: `ansible/roles/apps/tasks/myapp.yml`
2. Create template: `ansible/roles/apps/templates/myapp/docker-compose.yml.j2`
3. Add configuration to `inventory/group_vars/all/vars.yml`:
   ```yaml
   apps:
     myapp:
       enabled: true
       domain: myapp.onestack.cloud
       image: myapp/myapp:latest
       port: 3000
   ```
4. Add secrets to vault if needed
5. Include the task in `ansible/roles/apps/tasks/main.yml`

## Migrating to a new server

1. Run the new server helper:
   ```bash
   ./scripts/new-server.sh <new-server-ip>
   ```

2. Update inventory with the new server

3. Run backup on old server:
   ```bash
   ./scripts/deploy.sh backup
   ```

4. Copy backups to new server

5. Deploy to new server:
   ```bash
   ./scripts/deploy.sh all
   ```

6. Restore databases from backups

7. Update DNS to point to new server

## Security notes

- **Never commit unencrypted secrets** - always use `ansible-vault`
- The vault password file should be excluded from git (`.gitignore`)
- SSH keys should use strong passphrases
- Firewall is configured to only allow ports 22, 80, 443 by default
- All services run behind Traefik with automatic TLS certificates

## Backup and recovery

Backups are stored on the server at `/root/backups/YYYY-MM-DD/`:
- `postgres_all.sql.gz` - PostgreSQL databases
- `mariadb_all.sql.gz` - MariaDB databases
- `mongodb_all.archive.gz` - MongoDB databases
- `allbids_data/` - AllBids SQLite database
- `acme.json` - Let's Encrypt certificates

To restore PostgreSQL:
```bash
gunzip -c postgres_all.sql.gz | docker exec -i postgres_db psql -U onestack-cal
```

To restore MariaDB:
```bash
gunzip -c mariadb_all.sql.gz | docker exec -i mariadb mariadb -u root -p
```

## Troubleshooting

### SSH connection fails
```bash
# Test SSH manually
ssh root@server-ip

# Check SSH key
ssh-add -l
```

### Ansible can't find Python
```bash
# Install Python on remote server
ssh root@server-ip "apt-get update && apt-get install -y python3"
```

### Vault password issues
```bash
# Make sure password file exists and has correct permissions
ls -la ~/.ansible-vault-password
chmod 600 ~/.ansible-vault-password
```

### Check playbook without making changes
```bash
./scripts/deploy.sh all --check --diff
```
