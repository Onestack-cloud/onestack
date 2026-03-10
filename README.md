<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://onestack.cloud/images/logo_white_text.png">
    <source media="(prefers-color-scheme: light)" srcset="https://onestack.cloud/images/logo_black_text.png">
    <img src="https://onestack.cloud/images/logo_black_text.png" alt="Onestack" width="280">
  </picture>

  <p>One subscription, one interface, one click.<br>
  Manage open source alternatives to your SaaS tools from a single dashboard.</p>

  <p>
    <a href="https://onestack.cloud">Website</a> &middot;
    <a href="#quick-start">Quick start</a> &middot;
    <a href="#deployment">Deployment</a> &middot;
    <a href="#contributing">Contributing</a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/elixir-%234B275F.svg?logo=elixir&logoColor=white" alt="Elixir">
    <img src="https://img.shields.io/badge/phoenix-1.7-orange.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48cGF0aCBmaWxsPSIjZmZmIiBkPSJNMTIgMkw0IDdsMTIgNyA4IDQtMTItN3oiLz48L3N2Zz4=" alt="Phoenix">
    <img src="https://img.shields.io/badge/licence-AGPL--3.0-blue.svg" alt="Licence: AGPL-3.0">
    <img src="https://img.shields.io/badge/self--hosted-yes-green.svg" alt="Self-hosted">
  </p>
</div>

---

<div align="center">
  <img src="https://onestack.cloud/images/test_og_preview.png" alt="Onestack preview" width="700">
</div>

## What is Onestack?

Onestack replaces expensive SaaS subscriptions with self-hosted open source alternatives, managed through a single web interface. Instead of paying per-user fees to Slack, Linear, Figma, Calendly and others, you deploy their open source equivalents on your own infrastructure and manage everything from one place.

**For teams**, Onestack handles:
- Adding and removing users across all tools at once
- Shared infrastructure (one Postgres, one Redis) to reduce overhead
- Optional Stripe billing with graduated per-feature pricing
- Role-based access control and team management

**For self-hosters**, Onestack provides:
- Pre-configured Docker Compose files for each tool
- A unified Traefik reverse proxy setup with automatic TLS
- A web dashboard to manage it all, no Stripe required

## Included tools

| Tool | Replaces | Category |
|------|----------|----------|
| [Plane](https://github.com/makeplane/plane) | Linear, Jira | Project management |
| [Cal.com](https://github.com/calcom/cal.com) | Calendly | Scheduling |
| [Penpot](https://github.com/penpot/penpot) | Figma | Design |
| [Chatwoot](https://github.com/chatwoot/chatwoot) | Intercom | Customer support |
| [Matrix (Conduit)](https://gitlab.com/famedly/conduit) | Slack | Team chat |
| [Formbricks](https://github.com/formbricks/formbricks) | Typeform | Forms and surveys |
| [Documenso](https://github.com/documenso/documenso) | DocuSign | Document signing |
| [Kimai](https://github.com/kimai/kimai) | Toggl | Time tracking |
| [Castopod](https://github.com/ad-aures/castopod) | Buzzsprout | Podcast hosting |
| [LibreChat](https://github.com/danny-avila/LibreChat) | ChatGPT | AI chat |
| [Infisical](https://github.com/Infisical/infisical) | Doppler | Secrets management |
| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | Pingdom | Uptime monitoring |

Each tool has a ready-to-deploy Docker Compose configuration in [`onestack_products/`](onestack_products/).

## Tech stack

- **Backend**: Elixir, Phoenix Framework, Phoenix LiveView
- **Database**: SQLite (dev), PostgreSQL (production)
- **Frontend**: Tailwind CSS, DaisyUI, Alpine.js
- **Infrastructure**: Docker Compose, Traefik v3, Let's Encrypt
- **Payments**: Stripe (optional)

## Quick start

### Prerequisites

- Elixir 1.17+ and Erlang/OTP 26+
- Node.js 18+ (for asset compilation)
- SQLite3 (for local development)

### Development setup

```bash
# Clone the repository
git clone https://github.com/curiousgeorgios/onestack.git
cd onestack

# Copy environment config (Stripe keys are optional)
cp .env.example .env

# Install dependencies, create database and compile assets
mix setup

# Start the development server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to see the app.

> Onestack works without Stripe. If `STRIPE_API_KEY` is not set, billing features are automatically disabled and you can manage products and users directly.

### Running tests

```bash
mix test              # Run all tests
mix test --failed     # Re-run only failed tests
```

## Deployment

### Architecture overview

```
                    Internet
                       |
                   [ Traefik ]  ← automatic TLS via Let's Encrypt
                       |
        ┌──────────────┼──────────────┐
        |              |              |
   [ Onestack ]   [ Plane ]    [ Cal.com ]  ...
        |              |              |
        └──────┬───────┴──────────────┘
               |
         [ PostgreSQL ]  [ Redis ]  [ MariaDB ]
```

All services sit behind a single Traefik instance on the `traefik_default` Docker network. Each app gets a subdomain (e.g. `plane.yourdomain.com`) with automatic HTTPS certificates.

### Server deployment

```bash
# 1. Copy environment config and fill in your values
cp .env.example .env

# 2. Start shared infrastructure first
cd onestack_products/traefik_docker && docker compose up -d
cd ../databases/postgres && docker compose up -d
cd ../valkey_redis && docker compose up -d

# 3. Start individual services
cd ../../plane_docker && docker compose up -d
cd ../calcom_docker && docker compose up -d
# ... repeat for each tool you want to run

# 4. Start the Onestack management app
cd ../onestack_docker && docker compose up -d
```

Each product directory contains:
- `docker-compose.yml` with Traefik labels for automatic routing
- `.env.example` with the required configuration variables

### Environment variables

See [`.env.example`](.env.example) for the full list. Key variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `SECRET_KEY_BASE` | Yes | Phoenix session encryption. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Yes | Your domain (e.g. `onestack.cloud`) |
| `DATABASE_PATH` | Production | Path to the SQLite database file |
| `STRIPE_API_KEY` | No | Enables billing features when set |
| `STRIPE_PUBLIC_KEY` | No | Stripe publishable key for the checkout UI |
| `STRIPE_WEBHOOK_SECRET` | No | Stripe webhook signing secret |

## Project structure

```
onestack/
├── lib/
│   ├── onestack/                  # Business logic (contexts)
│   │   ├── accounts.ex            # User authentication
│   │   ├── teams.ex               # Team and organisation management
│   │   ├── catalog_monthly.ex     # Product catalogue
│   │   ├── member_manager.ex      # Cross-product user provisioning
│   │   └── subscriptions.ex       # Stripe subscription handling
│   └── onestack_web/              # Web layer
│       ├── live/                   # LiveView pages
│       ├── components/             # Reusable UI components
│       └── controllers/            # Traditional controllers
├── onestack_products/             # Docker configs for each tool
│   ├── traefik_docker/            # Reverse proxy
│   ├── databases/                 # Shared PostgreSQL, Redis, MariaDB
│   ├── plane_docker/              # Project management
│   ├── calcom_docker/             # Scheduling
│   ├── infisical_docker/          # Secrets management
│   └── ...                        # One directory per tool
├── infrastructure/                # Ansible playbooks and scripts
├── config/                        # Phoenix configuration
└── priv/                          # Migrations, seeds, static assets
```

## Adding a new product

1. Create a directory in `onestack_products/` with a `docker-compose.yml` and `.env.example`
2. Use Traefik labels for routing (see any existing product for the pattern)
3. Connect to the shared databases on the `traefik_default` network, or bundle your own
4. Add a database migration to insert the product into `products_central`
5. Implement `add_member_to_product` and `remove_member_from_product` in `Onestack.MemberManager`

## Contributing

Issues and pull requests are welcome. If you'd like to add a new tool integration, open an issue first to discuss the approach.

```bash
# Fork and clone the repo, then:
mix setup
mix test          # Make sure everything passes
mix phx.server    # Start developing
```

## Licence

[GNU Affero General Public Licence v3.0](https://www.gnu.org/licenses/agpl-3.0.en.html). See [LICENCE](LICENSE) for details.

## Acknowledgements

Onestack is built on top of these excellent open source projects:

[Cal.com](https://github.com/calcom/cal.com) &middot;
[Castopod](https://github.com/ad-aures/castopod) &middot;
[Chatwoot](https://github.com/chatwoot/chatwoot) &middot;
[Conduit](https://gitlab.com/famedly/conduit) &middot;
[Coturn](https://github.com/coturn/coturn) &middot;
[Documenso](https://github.com/documenso/documenso) &middot;
[Formbricks](https://github.com/formbricks/formbricks) &middot;
[Infisical](https://github.com/Infisical/infisical) &middot;
[Kimai](https://github.com/kimai/kimai) &middot;
[LibreChat](https://github.com/danny-avila/LibreChat) &middot;
[Penpot](https://github.com/penpot/penpot) &middot;
[Plane](https://github.com/makeplane/plane) &middot;
[Traefik](https://github.com/traefik/traefik) &middot;
[Uptime Kuma](https://github.com/louislam/uptime-kuma) &middot;
[Watchtower](https://github.com/containrrr/watchtower)
