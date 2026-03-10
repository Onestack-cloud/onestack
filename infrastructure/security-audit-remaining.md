# security audit — remaining recommendations

Audit date: 17 February 2026
Server: YOUR_SERVER_IP (onestack-prod), Ubuntu 24.04.3 LTS

## what was already implemented

| # | finding | fix applied |
|---|---------|-------------|
| C1 | Database ports exposed to internet | Bound to `127.0.0.1`, iptables raw + DOCKER-USER rules, SSH tunnel config |
| C2 | fail2ban missing | Installed with sshd jail (3 retries, 1h ban) |
| C3 | SSH password auth + X11 + MaxAuthTries | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| H1 | Borg empty passphrase | Passphrase set in script + repo key changed |
| H2 | .env files world-readable | All 13 files set to `chmod 600` |
| H3 | No rootkit detection | rkhunter installed |
| H4 | Traefik dashboard on 8080 | Port removed from docker-compose |
| M4 | No docker daemon.json | Created with log rotation + no-new-privileges |
| M5 | DB volumes not backed up | Dump script for all 4 engines, runs before borg |

---

## remaining recommendations

### M1 — apply pending security updates

**Priority:** medium
**Effort:** 10 minutes + brief service interruption for kernel updates

There are 18 pending package updates including docker-ce, libldap, linux-firmware, and initramfs-tools.

```bash
ssh root@YOUR_SERVER_IP
apt update && apt upgrade -y
# if kernel was updated:
reboot
```

After reboot, verify all containers come back up:
```bash
docker ps --format "{{.Names}}: {{.Status}}" | grep -E "unhealthy|Restarting|Exit"
```

Consider scheduling a monthly maintenance window for applying updates that unattended-upgrades doesn't cover (e.g., docker-ce, which comes from a third-party repo).

---

### M6 — create a sudo user and disable direct root login

**Priority:** medium
**Effort:** 15 minutes

Currently all SSH access is directly as root. Best practice is to use a non-root user with sudo privileges, limiting the blast radius of a compromised session.

```bash
ssh root@YOUR_SERVER_IP

# create user
adduser deploy
usermod -aG sudo deploy
usermod -aG docker deploy

# copy SSH key
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# test login in a separate terminal before locking root:
#   ssh deploy@YOUR_SERVER_IP
#   sudo whoami  (should print "root")

# once confirmed, disable root login:
echo "PermitRootLogin no" >> /etc/ssh/sshd_config.d/99-hardening.conf
systemctl reload ssh
```

After this, update `~/.ssh/config` locally to change `User root` to `User deploy` for both `onestack-monolith` and `onestack-db` entries.

**Note:** the backup script, db_backup script, cron jobs, and docker-compose files all run as root. The `deploy` user accesses them via `sudo`. Docker commands work without sudo because of the `docker` group membership.

---

### L1 — extend unattended-upgrades to cover docker

**Priority:** low
**Effort:** 5 minutes

Currently only Ubuntu security updates are auto-installed. Docker CE updates from the docker repo are not covered.

```bash
ssh root@YOUR_SERVER_IP

# add docker repo to unattended-upgrades
cat >> /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'

// Docker CE security updates
Unattended-Upgrade::Allowed-Origins {
    "Docker:noble";
};
EOF

# verify config is valid
unattended-upgrade --dry-run 2>&1 | tail -5
```

**Caveat:** auto-updating docker-ce can restart the Docker daemon, which briefly restarts all containers. If uptime is critical, you may prefer to keep docker updates manual and just do them during maintenance windows.

---

### L3 — clean up netdata-updater temp files

**Priority:** low
**Effort:** 2 minutes

There are ~40 stale `netdata-updater-*` directories and log files in `/tmp/`. The daily netdata updater cron job isn't cleaning up after itself.

```bash
ssh root@YOUR_SERVER_IP

# one-time cleanup
rm -rf /tmp/netdata-updater-* /tmp/netdata-updater.log.*

# add cleanup to the daily cron (optional)
cat > /etc/cron.daily/netdata-cleanup << 'EOF'
#!/bin/bash
find /tmp -maxdepth 1 -name "netdata-updater-*" -mtime +1 -exec rm -rf {} +
find /tmp -maxdepth 1 -name "netdata-updater.log.*" -mtime +1 -delete
EOF
chmod +x /etc/cron.daily/netdata-cleanup
```

---

### L4 — docker socket awareness

**Priority:** low (informational)
**Effort:** n/a

The Docker socket (`/var/run/docker.sock`) is accessible to the `docker` group. This is standard Docker behaviour, but be aware that **any user in the docker group effectively has root access** to the host — they can mount the host filesystem into a container, access all secrets, etc.

Current docker group members should be audited periodically:
```bash
getent group docker
```

If you create the `deploy` sudo user (M6) and add them to the `docker` group, understand this is equivalent to giving them root. This is fine for an admin user but should not be extended to application service accounts.

---

## files modified on the server during this audit

For reference, these are all files created or modified:

| file | purpose |
|------|---------|
| `/etc/fail2ban/jail.local` | fail2ban sshd jail config |
| `/etc/ssh/sshd_config.d/99-hardening.conf` | SSH hardening (no password, MaxAuthTries 3, no X11) |
| `/usr/local/bin/backup.sh` | Added borg passphrase + db dump call |
| `/usr/local/bin/db_backup.sh` | New: database dump script (pg, mariadb, mongo, valkey) |
| `/etc/docker/daemon.json` | New: Docker daemon config (log rotation, no-new-privileges) |
| `/etc/docker/docker-user-rules.sh` | New: iptables rules persistence script |
| `/etc/systemd/system/docker-user-iptables.service` | New: systemd service for iptables persistence |
| `/root/traefik_docker/docker-compose.yml` | DB ports bound to 127.0.0.1, port 8080 removed |
| `/root/databases/mariadb/docker-compose.yml` | Port 3336 bound to 127.0.0.1 |
| `/root/databases/mongodb/docker-compose.yml` | Port 27018 bound to 127.0.0.1 |

Backups of modified docker-compose files were saved as `docker-compose.yml.bak*` in each directory.
