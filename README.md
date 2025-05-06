<div align="center">
  <img src="https://onestack.cloud/images/logo_white_text.png" alt="Onestack Logo" width="300">
  <p><em>One interface to manage all your open source tools</em></p>
  
  <p>
    <img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="License: AGPL-3.0">
    <img src="https://img.shields.io/badge/status-experimental-orange.svg" alt="Status: Experimental">
  </p>
</div>

---

> **⚠️ DISCLAIMER:** This repository is currently **fully untested** and serves only as a way to gauge interest in Onestack. I'll try my best to address any issues raised and I'll take development more seriously if the repo gets more traction.

> **⚠️ IMPORTANT NOTE:** The current code is messy and still has Stripe payment processing tightly coupled in various places. To use this project without incurring charges, you must enter Stripe testing keys (not production keys) in the configuration. Please do not use production keys unless you fully understand the billing implications.

**[Visit https://onestack.cloud](https://onestack.cloud) to learn more about Onestack and see what the application UI looks like!**

## 📋 Table of Contents

- [📋 Table of Contents](#-table-of-contents)
- [🔍 Overview](#-overview)
- [✨ Features](#-features)
- [🏗️ Project Structure](#️-project-structure)
- [🚀 Deployment](#-deployment)
  - [Environment Setup](#environment-setup)
  - [Other Services](#other-services)
    - [Coturn](#coturn)
- [💻 Development](#-development)
  - [Making Changes to Onestack Web App](#making-changes-to-onestack-web-app)
  - [Adding a New Product](#adding-a-new-product)
- [🔐 Google OAuth Scopes](#-google-oauth-scopes)
- [⚠️ Current Limitations](#️-current-limitations)
- [📝 TODO List](#-todo-list)
- [📄 License](#-license)
- [🙏 Acknowledgements](#-acknowledgements)

## 🔍 Overview

Onestack is a unified platform to access and manage various open source tools from a single interface. It simplifies user management, access control, and billing for multiple open source services.

The project streamlines administration by providing:
- Centralized user management across multiple tools
- Simplified onboarding and offboarding processes
- Unified access control and permissions
- Consolidated billing and resource allocation

## ✨ Features

- **Unified Management Interface**: Add/remove users across multiple services at once
- **Shared Infrastructure**: Multiple services running on shared databases to reduce overhead
- **Simplified Deployment**: Streamlined setup for complex open source tools
- **Centralized Authentication**: Manage access across tools in one place

## 🏗️ Project Structure

Onestack consists of two main components:

1. **Docker Configurations**: All the configurations required to run OSS tools based on shared databases (one PostgreSQL instance, one MariaDB instance, etc.)
2. **Web Interface**: The Onestack management application for administering services and users

## 🚀 Deployment

### Environment Setup

```bash
# 1. Navigate to the products directory
cd onestack_products

# 2. Make scripts executable
chmod +x *.sh

# 3. Generate environment configuration
bash 1-generate-env.sh

# For server deployment (optional)
# This step copies necessary files to your server
# First, edit the script to configure your server details:
#   SSH_USER="your_user"
#   SSH_HOST="your.host.tld"
#   SSH_KEY="/path/to/your/id_rsa"   # optional, if you need a specific key
#   REMOTE_PATH="/root"
bash 2-copy-files-to-server.sh

# 4. Deploy all services
bash 3-deploy-all.sh
```

### Other Services

#### Coturn

Coturn needs to be deployed outside of Docker due to limitations with the number of ports required:

```bash
# 1. Install Coturn
apt install coturn

# 2. Stop the default service
service coturn stop

# 3. Launch with custom configuration
coturn -c /root/matrix_docker/coturn.conf
```

## 💻 Development

### Making Changes to Onestack Web App

To start the Phoenix server:

```bash
# Install and setup dependencies
mix setup

# Start the Phoenix endpoint
mix phx.server

# Or start it inside IEx
iex -S mix phx.server
```

You can then visit [`localhost:4000`](http://localhost:4000) from your browser.

### Adding a New Product

To include a new product in Onestack:

1. Determine required database and services for the backend
2. Configure backend services if needed
3. Implement member management functions:
   - `Onestack.MemberManager.add_member_to_product`
   - `Onestack.MemberManager.remove_member_from_product`
4. Create a new subdirectory with:
   - Docker Compose configuration
   - Template environment file
5. Update `root.env` with any required global variables

## 🔐 Google OAuth Scopes

The following scopes are required for various integrations:

- **Cal**:
  - `.../auth/calendar.readonly`
  - `.../auth/calendar.events`
- **Formbricks**:
  - `.../auth/spreadsheets`

## ⚠️ Current Limitations

- **Coturn Service**: Must be run natively due to Docker limitations with exposing a large number of ports
  - This is only required for calls in Matrix
  - Can be substituted with another cloud-based TURN server
  
- **Local Development**: `deploy-all.sh` supports a `--local` flag for testing services locally, but the local TLS development config hasn't been thoroughly tested yet

- **n8n Integration**: While configuration files for n8n are included for personal use, it cannot be distributed with Onestack due to licensing restrictions 😊

## 📝 TODO List

- [ ] Update Coturn/Matrix config to use TLS
- [ ] Add `remove_member_from_product` for "matrix" in `member_manager.ex`
- [ ] Implement handling for reactivation of existing users

## 📄 License

This project is licensed under the [GNU Affero General Public License v3.0](https://www.gnu.org/licenses/agpl-3.0.en.html) - see the LICENSE file for details.

## 🙏 Acknowledgements

- [**Cal.com**](https://github.com/calcom/cal.com) - Scheduling infrastructure for everyone
- [**Documenso**](https://github.com/documenso/documenso) - The Open Source DocuSign Alternative
- [**Formbricks**](https://github.com/formbricks/formbricks) - Open-source survey & experience management
- [**Penpot**](https://github.com/penpot/penpot) - Design freedom for teams
- [**Conduit**](https://gitlab.com/famedly/conduit) - A Matrix homeserver written in Rust
- [**Kimai**](https://github.com/kimai/kimai) - Free & open source time-tracking
- [**Uptime Kuma**](https://github.com/louislam/uptime-kuma) - Self-hosted monitoring tool
- [**Plane**](https://github.com/makeplane/plane) - Open source project management
- [**Traefik**](https://github.com/traefik/traefik) - Cloud-native application proxy
- [**Castopod**](https://github.com/ad-aures/castopod) - Open-source podcast hosting platform
- [**LibreChat**](https://github.com/danny-avila/LibreChat) - Enhanced ChatGPT clone
- [**Chatwoot**](https://github.com/chatwoot/chatwoot) - Open-source customer support platform
- [**Watchtower**](https://github.com/containrrr/watchtower) - Automating Docker container updates
- [**Coturn**](https://github.com/coturn/coturn) - TURN/STUN server for WebRTC
