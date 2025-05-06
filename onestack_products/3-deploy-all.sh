#!/usr/bin/env bash
set -euo pipefail

# Parse command line arguments
LOCAL_ENV=false
for arg in "$@"; do
  case $arg in
    --local|--dev)
      LOCAL_ENV=true
      shift
      ;;
    *)
      # Unknown option
      ;;
  esac
done

# If local environment, set up environment variables for local development
if [[ "$LOCAL_ENV" == true ]]; then
  echo "🧪 Setting up local development environment with self-signed certificates"
  export TOP_LEVEL_DOMAIN=localhost
  export CERT_RESOLVER=localcert
  
  # Create local certificates resolver configuration for Traefik
  cat > ./traefik_docker/local_cert_config.yml << EOF
# Local development TLS settings
tls:
  options:
    default:
      sniStrict: false
      insecureSkipVerify: true

# Set up a self-signed cert for local development
certificatesResolvers:
  localcert:
    # We're generating a self-signed certificate for local development
    # No need for ACME/Let's Encrypt in local dev
    tls:
      selfSigned: {}
EOF

  # Make sure traefik knows to use the local config
  echo "Configuring Traefik for local development..."
  if [[ -d "traefik_docker" ]]; then
    # Enable dashboard and insecure mode for local development
    sed -i'.bak' 's/insecure: false/insecure: true/g' traefik_docker/traefik.yml
    
    # Add the local_cert_config.yml to the Traefik volumes in docker-compose.yml
    if ! grep -q "local_cert_config.yml" traefik_docker/docker-compose.yml; then
      sed -i'.bak' '/traefik.yml/a\            - ./local_cert_config.yml:/etc/traefik/local_cert_config.yml' traefik_docker/docker-compose.yml
    fi
    
    # Add environment variables if not present
    if ! grep -q "TOP_LEVEL_DOMAIN" traefik_docker/docker-compose.yml; then
      sed -i'.bak' '/volumes/i\        environment:\n            - TOP_LEVEL_DOMAIN=${TOP_LEVEL_DOMAIN:-localhost}\n            - CERT_RESOLVER=${CERT_RESOLVER:-letsencrypt}' traefik_docker/docker-compose.yml
    fi
  fi
else
  echo "🌐 Setting up production environment"
  export CERT_RESOLVER=letsencrypt
fi

# iterate every first‐level subdirectory
for dir in */ ; do
  # if it has a docker‑compose.yml (or .yaml), deploy it
  if [[ -f "$dir/docker-compose.yml" || -f "$dir/docker-compose.yaml" ]]; then
    echo "📦 Deploying stack in $dir…"
    (
      cd "$dir"
      # Pass the environment variables to the docker compose command
      if [[ "$LOCAL_ENV" == true ]]; then
        export TOP_LEVEL_DOMAIN=localhost
        export CERT_RESOLVER=localcert
        docker compose up -d
      else
        docker compose up -d
      fi
    )
  else
    echo "⏭ Skipping $dir (no compose file)"
  fi
done

echo "✅ All done."

# Cleanup backup files
find . -name "*.bak" -delete