# Phoenix/LiveView upgrade + optimistic UI

## Overview

Upgrade Onestack from Phoenix 1.7/LiveView 0.20 to Phoenix 1.8/LiveView 1.1, then apply optimistic UI patterns across key views.

## Phase 1: dependency upgrade

### mix.exs changes

| Dependency | Current | Target |
|---|---|---|
| `phoenix` | `~> 1.7.11` | `~> 1.8` |
| `phoenix_live_view` | `~> 0.20.2` | `~> 1.1` |
| `phoenix_ecto` | `~> 4.4` | `~> 4.5` |
| `phoenix_html` | `~> 4.0` | `~> 4.1` |
| `phoenix_live_dashboard` | `~> 0.8.3` | `~> 0.8.7` |
| `floki` | `">= 0.30.0"` | Remove |
| `lazy_html` | N/A | Add `{:lazy_html, ">= 0.0.0", only: :test}` |

Add to `def project`: `compilers: [:phoenix_live_view] ++ Mix.compilers()`

### Breaking change fixes

#### 1. Remove `phx-feedback-for` (core_components.ex)

4 occurrences at lines 359, 384, 414, 438. Remove the attribute from wrapper divs and replace error filtering with `used_input?/1`:

```elixir
# Before
<div phx-feedback-for={@name}>
# After
<div>

# Before (error component, line 482)
<p class="... phx-no-feedback:hidden">
# After: filter errors server-side
errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []
```

#### 2. Remove `phx-no-feedback` Tailwind variant (tailwind.config.js)

Remove lines 74-78 (the `addVariant("phx-no-feedback", ...)` plugin).

#### 3. Replace `push_redirect` with `push_navigate`

- `application_ui_live.ex` lines 28, 31
- `role_redirect_live.ex` line 34

#### 4. Replace `:fl-contains` test selectors

- `user_login_live_test.exs` lines 66, 80: `element(~s|#log_in a:fl-contains("Sign up here")|)` -> `element("#log_in a", "Sign up here")`
- `user_registration_live_test.exs` line 73: same pattern

#### 5. Update esbuild config (config.exs)

Update target from `es2017` to `es2022`, add `--alias:@=.` flag, update `NODE_PATH` to include build path.

#### 6. Optional dev config (config/dev.exs)

Add LiveView debug options:
```elixir
config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
```

## Phase 2: optimistic UI patterns

### Pattern A: async assigns (`assign_async`)

Load data in background without blocking initial render.

**Landing page** (`landing_live.ex`): Load product catalogue and pricing data async on mount.

**Teams management** (`teams_live.ex`): Load team members and invitations async.

**Features management** (`features_live.ex`): Load subscription stats and product catalogue async.

**Feedback** (`feedback_live/index.ex`): Load feedback list async on mount.

### Pattern B: CSS loading states

Add `phx-disable-with` to all form submit buttons across:
- User settings forms (email, password)
- Feedback submission form
- Team invitation form
- Onboarding forms

Add CSS transitions for `phx-click-loading` on interactive elements:
- Vote buttons in feedback
- Feature toggle buttons
- Team member action buttons

### Pattern C: optimistic handle_event

Update assigns immediately in `handle_event`, confirm in background.

**Feedback voting** (`feedback_live/index.ex`): Increment vote count in stream immediately, persist via `start_async`.

**Feature toggles** (`features_live.ex`): Show toggle state change immediately, update subscription in background.

**Team member removal** (`teams_live.ex`): Remove from assigns list immediately, delete in background.

### Pattern D: start_async for expensive operations

**Onboarding** (`onboarding_live.ex`): Already uses `send(self(), {:create_payment_intent})`. Migrate to `start_async` for cleaner pattern with built-in error handling.

**User settings** (`user_settings_live.ex`): Show success flash immediately on valid changeset, persist in background.

**Team invitations** (`teams_live.ex`): Add emails to pending list immediately, send invitations via `start_async`.

## Files changed

### Phase 1 (breaking changes)
- `mix.exs`
- `lib/onestack_web/components/core_components.ex`
- `assets/tailwind.config.js`
- `lib/onestack_web/live/application_ui/application_ui_live.ex`
- `lib/onestack_web/live/role_redirect_live.ex`
- `test/onestack_web/live/user_login_live_test.exs`
- `test/onestack_web/live/user_registration_live_test.exs`
- `config/config.exs`
- `config/dev.exs`

### Phase 2 (optimistic UI)
- `lib/onestack_web/live/landing_live/landing_live.ex`
- `lib/onestack_web/live/feedback_live/index.ex`
- `lib/onestack_web/live/application_ui/admin_live/features_live.ex`
- `lib/onestack_web/live/application_ui/admin_live/teams_live.ex`
- `lib/onestack_web/live/user_settings_live.ex`
- `lib/onestack_web/live/onboarding_live/onboarding_live.ex`
- `lib/onestack_web/components/core_components.ex` (add loading CSS)

## Testing

- All existing tests must pass after phase 1
- Update test selectors for LiveView 1.1 syntax
- Add tests for async loading states where new behaviour is introduced
