# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Onestack is a Phoenix LiveView application that provides a platform for managing containerized applications and services. It's built with Elixir/Phoenix and includes user authentication, team management, subscription billing via Stripe, and supports multi-tenant architecture with subdomain routing.

## Common Commands

### Development Setup
```bash
mix setup          # Install dependencies and setup database
mix phx.server     # Start development server (localhost:4000)
iex -S mix phx.server  # Start server with interactive Elixir shell
```

### Testing
```bash
mix test           # Run all tests
mix test --failed  # Run only failed tests
mix test test/path/to/test.exs  # Run specific test file
```

### Database Management
```bash
mix ecto.create    # Create database
mix ecto.migrate   # Run migrations
mix ecto.reset     # Drop, create, migrate and seed database
mix ecto.setup     # Create, migrate and seed database
```

### Asset Management
```bash
mix assets.setup   # Install Tailwind and ESBuild dependencies
mix assets.build   # Build assets for development
mix assets.deploy  # Build and minify assets for production
```

## Architecture

### Core Technology Stack
- **Phoenix Framework**: Web framework with LiveView for real-time UI
- **Ecto**: Database ORM with SQLite (dev) and support for PostgreSQL/MySQL
- **Tailwind CSS + DaisyUI/Flowbite**: Styling and UI components  
- **Alpine.js**: Minimal JavaScript framework
- **Stripe**: Payment processing and subscription management

### Application Structure

#### Contexts (Business Logic Layer)
- `Onestack.Accounts` - User management and authentication
- `Onestack.Teams` - Team/organization management with invitations
- `Onestack.Subscriptions` - Stripe subscription and customer handling
- `Onestack.Payments` - Payment processing
- `Onestack.Feedback` - User feedback system with comments and voting
- `Onestack.CatalogMonthly` - Product catalog management
- `Onestack.MatrixAccounts` - Matrix/Element integration for chat services

#### Web Layer (Phoenix LiveView)
- Subdomain-based routing (`app.`, `feedback.`, `admin.`)
- Role-based access control (super_admin, admin, member)
- Multiple layout types (sidebar_live, topbar_live)
- Real-time UI updates via LiveView

#### Key LiveView Components
- Landing page and pricing
- User authentication flows (registration, login, password reset)
- Team management and member invitations
- Admin panels for different user roles
- Product catalog and feature management
- Feedback collection system

### Directory Structure
- `lib/onestack/` - Context modules (business logic)
- `lib/onestack_web/` - Web interface (controllers, LiveViews, components)
- `lib/onestack_web/live/` - LiveView modules organized by feature
- `onestack_products/` - Docker Compose configurations for various services
- `assets/` - Frontend assets (CSS, JS, Tailwind config)
- `priv/static/` - Compiled static assets
- `test/` - Test files mirroring lib structure

## Development Guidelines

### Database
- Uses SQLite for development (onestack_dev.db)
- Migrations in `priv/repo/migrations/`
- Seeds in `priv/repo/seeds.exs`

### Authentication & Authorization
- Phoenix authentication with `OnestackWeb.UserAuth`
- Role-based routing with `ensure_admin`, `ensure_super_admin` hooks
- Session-based authentication with CSRF protection

### Routing Patterns
- Subdomain routing for different app sections
- LiveView sessions with proper authentication mounting
- Pipeline-based request processing with plugs

### Testing
- Context tests in `test/onestack/`
- Web tests in `test/onestack_web/`
- Uses ExUnit with Phoenix test helpers
- Database cleanup between tests via Ecto.Adapters.SQL.Sandbox

### Frontend
- Tailwind CSS with component libraries (DaisyUI, Flowbite, Preline)
- Alpine.js for interactive components
- Phoenix LiveView for real-time updates
- ESBuild for JavaScript bundling