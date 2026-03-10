# Phoenix/LiveView upgrade + optimistic UI implementation plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade from Phoenix 1.7/LiveView 0.20 to Phoenix 1.8/LiveView 1.1, then apply optimistic UI patterns across all key views.

**Architecture:** Phased upgrade: first update dependencies and fix all breaking changes (phase 1), then layer on optimistic UI patterns using assign_async, start_async, CSS loading states and optimistic handle_event (phase 2). Each phase ends with a full test suite pass.

**Tech Stack:** Elixir, Phoenix 1.8, LiveView 1.1, Tailwind CSS, SQLite

---

## Chunk 1: dependency upgrade and breaking changes

### Task 1: update mix.exs dependencies

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Update dependency versions and add compilers**

In `mix.exs`, make these changes:

```elixir
# In def project, add compilers key:
def project do
  [
    app: :onestack,
    version: "1.0.0",
    elixir: "~> 1.14",
    elixirc_paths: elixirc_paths(Mix.env()),
    compilers: [:phoenix_live_view] ++ Mix.compilers(),
    start_permanent: Mix.env() == :prod,
    aliases: aliases(),
    deps: deps()
  ]
end

# In deps(), update these lines:
{:phoenix, "~> 1.8"},
{:phoenix_ecto, "~> 4.5"},
{:phoenix_html, "~> 4.1"},
{:phoenix_live_view, "~> 1.1"},
{:lazy_html, ">= 0.0.0", only: :test},
{:phoenix_live_dashboard, "~> 0.8.7"},

# Remove the floki line:
# {:floki, ">= 0.30.0", only: :test},  <-- DELETE THIS
```

- [ ] **Step 2: Fetch updated dependencies**

Run: `mix deps.get`
Expected: All dependencies resolve successfully. No version conflicts.

- [ ] **Step 3: Compile to check for warnings**

Run: `mix compile --warnings-as-errors 2>&1 | head -50`
Expected: May produce warnings about deprecated functions; note them for next tasks. Should compile without errors.

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: upgrade Phoenix 1.8, LiveView 1.1, add lazy_html"
```

---

### Task 2: remove phx-feedback-for and phx-no-feedback from core_components.ex

**Files:**
- Modify: `lib/onestack_web/components/core_components.ex`

- [ ] **Step 1: Update the input function that takes a FormField to filter errors with used_input?**

Replace the existing `input(%{field: %Phoenix.HTML.FormField{} = field} = assigns)` function (around line 343) so it filters errors using `used_input?`:

```elixir
def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
  errors = if Phoenix.Component.used_input?(field), do: Enum.map(field.errors, &translate_error(&1)), else: []

  assigns
  |> assign(field: nil, id: assigns.id || field.id)
  |> assign(:errors, errors)
  |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
  |> assign_new(:value, fn -> field.value end)
  |> input()
end
```

- [ ] **Step 2: Remove phx-feedback-for from checkbox input (line 359)**

Change:
```heex
<div class="form-control" phx-feedback-for={@name}>
```
To:
```heex
<div class="form-control">
```

- [ ] **Step 3: Remove phx-feedback-for from select input (line 384)**

Change:
```heex
<div phx-feedback-for={@name}>
```
To:
```heex
<div>
```

- [ ] **Step 4: Remove phx-feedback-for from textarea input (line 414)**

Change:
```heex
<div phx-feedback-for={@name}>
```
To:
```heex
<div>
```

- [ ] **Step 5: Remove phx-feedback-for from generic input (line 438)**

Change:
```heex
<div phx-feedback-for={@name}>
```
To:
```heex
<div>
```

- [ ] **Step 6: Remove phx-no-feedback:hidden from error component (line 482)**

Change:
```heex
<p class="mt-3 flex items-center gap-1 text-sm font-medium text-red-600 dark:text-red-400 phx-no-feedback:hidden">
```
To:
```heex
<p class="mt-3 flex items-center gap-1 text-sm font-medium text-red-600 dark:text-red-400">
```

- [ ] **Step 7: Compile to verify no errors**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 8: Commit**

```bash
git add lib/onestack_web/components/core_components.ex
git commit -m "fix: remove phx-feedback-for, use used_input? for LiveView 1.1"
```

---

### Task 3: remove phx-no-feedback Tailwind variant

**Files:**
- Modify: `assets/tailwind.config.js`

- [ ] **Step 1: Remove the phx-no-feedback variant plugin (lines 74-79)**

Remove this block from the plugins array:
```javascript
plugin(({ addVariant }) =>
  addVariant("phx-no-feedback", [
    ".phx-no-feedback&",
    ".phx-no-feedback &",
  ]),
),
```

- [ ] **Step 2: Build assets to verify**

Run: `mix assets.build`
Expected: Assets build successfully with no errors.

- [ ] **Step 3: Commit**

```bash
git add assets/tailwind.config.js
git commit -m "fix: remove phx-no-feedback Tailwind variant for LiveView 1.1"
```

---

### Task 4: replace push_redirect with push_navigate

**Files:**
- Modify: `lib/onestack_web/live/application_ui/application_ui_live.ex`
- Modify: `lib/onestack_web/live/role_redirect_live.ex`

- [ ] **Step 1: Update application_ui_live.ex (lines 28 and 31)**

Change:
```elixir
{:ok, socket |> push_redirect(to: "/admin/features")}
```
To:
```elixir
{:ok, socket |> push_navigate(to: "/admin/features")}
```

And:
```elixir
{:ok, socket |> push_redirect(to: "/user/features")}
```
To:
```elixir
{:ok, socket |> push_navigate(to: "/user/features")}
```

- [ ] **Step 2: Update role_redirect_live.ex (line 34)**

Change:
```elixir
{:ok, push_redirect(socket, to: redirect_path)}
```
To:
```elixir
{:ok, push_navigate(socket, to: redirect_path)}
```

- [ ] **Step 3: Search for any remaining push_redirect usage**

Run: `grep -r "push_redirect" lib/`
Expected: No results.

- [ ] **Step 4: Commit**

```bash
git add lib/onestack_web/live/application_ui/application_ui_live.ex lib/onestack_web/live/role_redirect_live.ex
git commit -m "fix: replace push_redirect with push_navigate for LiveView 1.1"
```

---

### Task 5: update test selectors from fl-contains to text filter

**Files:**
- Modify: `test/onestack_web/live/user_login_live_test.exs`
- Modify: `test/onestack_web/live/user_registration_live_test.exs`

- [ ] **Step 1: Update user_login_live_test.exs (line 66)**

Change:
```elixir
|> element(~s|#log_in a:fl-contains("Sign up here")|)
```
To:
```elixir
|> element("#log_in a", "Sign up here")
```

- [ ] **Step 2: Update user_login_live_test.exs (line 80)**

Change:
```elixir
|> element(~s|#log_in a:fl-contains("Forgot password?")|)
```
To:
```elixir
|> element("#log_in a", "Forgot password?")
```

- [ ] **Step 3: Update user_registration_live_test.exs (line 73)**

Change:
```elixir
|> element(~s|#log_in a:fl-contains("Log in")|)
```
To:
```elixir
|> element("#log_in a", "Log in")
```

- [ ] **Step 4: Search for any remaining fl-contains usage**

Run: `grep -r "fl-contains" test/`
Expected: No results.

- [ ] **Step 5: Commit**

```bash
git add test/onestack_web/live/user_login_live_test.exs test/onestack_web/live/user_registration_live_test.exs
git commit -m "fix: replace fl-contains selectors with text filter for LiveView 1.1"
```

---

### Task 6: update esbuild config

**Files:**
- Modify: `config/config.exs`

- [ ] **Step 1: Update esbuild configuration (lines 51-58)**

Change:
```elixir
config :esbuild,
  version: "0.17.11",
  onestack: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```
To:
```elixir
config :esbuild,
  version: "0.17.11",
  onestack: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
```

- [ ] **Step 2: Add LiveView debug config to dev.exs**

The file already has `config :phoenix_live_view, :debug_heex_annotations, true` on line 119. Add runtime checks below it:

```elixir
config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
```

- [ ] **Step 3: Build assets to verify**

Run: `mix assets.build`
Expected: Assets build successfully.

- [ ] **Step 4: Commit**

```bash
git add config/config.exs config/dev.exs
git commit -m "config: update esbuild target to es2022, add LV debug checks"
```

---

### Task 7: run full test suite

- [ ] **Step 1: Run all tests**

Run: `mix test`
Expected: All tests pass. If any fail, fix them before proceeding.

- [ ] **Step 2: Start the dev server and verify it boots**

Run: `mix phx.server` (manual check, Ctrl+C to stop)
Expected: Server starts without errors on localhost:4000.

- [ ] **Step 3: Commit any remaining fixes**

If any fixes were needed, commit them with an appropriate message.

---

## Chunk 2: optimistic UI, landing page and feedback

### Task 8: landing page async data loading

**Files:**
- Modify: `lib/onestack_web/live/landing_live/landing_live.ex`

- [ ] **Step 1: Use assign_async for product catalogue loading**

Update the `mount/3` function to load products asynchronously. The landing page should render immediately with a loading state, then populate when data arrives.

```elixir
@impl true
def mount(_params, session, socket) do
  current_user =
    case session["user_token"] do
      nil -> nil
      user_token -> Accounts.get_user_by_session_token(user_token)
    end

  socket =
    socket
    |> assign(:current_user, current_user)
    |> assign_async(:product_data, fn ->
      products = CatalogMonthly.list_products()
      features = CatalogMonthly.ProductMetadata.all_products()
      testimonial_cards = TestimonialData.testimonial_cards()

      prepared_products =
        Enum.map(products, fn product ->
          product
          |> Map.from_struct()
          |> Map.drop([:__meta__])
          |> Map.new(fn {k, v} ->
            {k,
             if is_struct(v, Decimal) do
               Decimal.to_float(v)
             else
               v
             end}
          end)
        end)

      {:ok,
       %{
         products: products,
         prepared_products: Jason.encode!(prepared_products),
         features: features,
         testimonial_cards: testimonial_cards
       }}
    end)

  {:ok, socket}
end
```

Note: The template will need to handle the `@product_data` async assign with its `.loading`, `.ok?` and `.result` fields. Update template references from `@products` to `@product_data.result.products` etc., wrapped in a loading check.

- [ ] **Step 2: Compile and verify**

Run: `mix compile`
Expected: No errors. Some template warnings about undefined assigns are expected until the template is updated.

- [ ] **Step 3: Commit**

```bash
git add lib/onestack_web/live/landing_live/landing_live.ex
git commit -m "feat: async product loading on landing page"
```

---

### Task 9: feedback optimistic voting

**Files:**
- Modify: `lib/onestack_web/live/feedback_live/index.ex`

- [ ] **Step 1: Make upvote handler optimistic**

Replace the current `handle_event("upvote", ...)` (lines 89-104) with an optimistic version that updates the stream immediately, then persists in the background:

```elixir
@impl true
def handle_event("upvote", %{"id" => id}, socket) do
  case socket.assigns.current_user do
    nil ->
      {:noreply,
       socket
       |> put_flash(:error, "You must be logged in to upvote.")
       |> redirect(to: ~p"/users/log_in")}

    user ->
      feedback = Onestack.Feedback.get_feedback!(id)
      currently_upvoted = Map.get(feedback, :has_upvoted, false)

      # Optimistically update the stream
      optimistic_feedback =
        feedback
        |> Map.put(:has_upvoted, !currently_upvoted)
        |> Map.update!(:upvote_count, fn count ->
          if currently_upvoted, do: max(count - 1, 0), else: count + 1
        end)

      socket = stream_insert(socket, :feedbacks, optimistic_feedback)

      # Persist in the background
      start_async(socket, {:toggle_upvote, id}, fn ->
        Onestack.Feedback.toggle_upvote(feedback, user)
      end)
  end
end

@impl true
def handle_async({:toggle_upvote, _id}, {:ok, {:ok, _}}, socket) do
  # Success, optimistic update was correct, nothing to do
  {:noreply, socket}
end

def handle_async({:toggle_upvote, _id}, {:ok, {:error, _}}, socket) do
  # Failed, reload to correct the optimistic update
  {:noreply, load_feedbacks(socket)}
end

def handle_async({:toggle_upvote, _id}, {:exit, _reason}, socket) do
  {:noreply, load_feedbacks(socket)}
end
```

- [ ] **Step 2: Compile and verify**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/onestack_web/live/feedback_live/index.ex
git commit -m "feat: optimistic upvoting in feedback view"
```

---

## Chunk 3: optimistic UI, features and teams

### Task 10: features_live optimistic toggle with loading state

**Files:**
- Modify: `lib/onestack_web/live/application_ui/admin_live/features_live.ex`

- [ ] **Step 1: The features_live already uses `send(self(), ...)` for async operations and has an `updating` assign for loading state. This is a reasonable pattern. Add phx-disable-with to the update_subscription button in the template.**

Search the template (HEEx) for the subscription update button and add `phx-disable-with="Updating..."` to it. The `updating` assign is already used to show a loading state, so the existing pattern is good.

No server-side changes needed; the existing `send(self(), {:run_update_subscription, ...})` pattern is already effectively async.

- [ ] **Step 2: Commit**

```bash
git add lib/onestack_web/live/application_ui/admin_live/features_live.ex
git commit -m "feat: add loading feedback to feature toggle buttons"
```

---

### Task 11: teams_live optimistic member removal

**Files:**
- Modify: `lib/onestack_web/live/application_ui/admin_live/teams_live.ex`

- [ ] **Step 1: Make member removal optimistic**

In `handle_event("remove_member", ...)` (line 163), update the UI immediately before doing the actual removal. Replace the handler:

```elixir
def handle_event("remove_member", %{"email" => email}, socket) do
  current_user = socket.assigns.current_user

  # Optimistically remove from UI immediately
  updated_team_members =
    Enum.reject(socket.assigns.team_members, fn member ->
      member == email || (is_map(member) && Map.get(member, :email) == email)
    end)

  socket =
    socket
    |> assign(team_members: updated_team_members)
    |> assign(num_users: calculate_num_users(updated_team_members))

  # Perform actual removal in background
  {:noreply,
   start_async(socket, {:remove_member, email}, fn ->
     # Remove pending invitation if exists
     case Teams.get_pending_invitation_by_email(email) do
       %Teams.Invitation{} = invitation -> Teams.delete_invitation(invitation)
       nil -> :ok
     end

     # Remove the team member
     case Teams.remove_team_member(current_user, email) do
       {:ok, _team} ->
         product_names =
           get_product_names(socket.assigns.stats.subscribed_products)

         Onestack.MemberManager.remove_member(email, product_names)

         updated_team_members = Teams.list_team_members_by_admin(current_user)

         update_subscription_pricing_after_member_change(
           current_user,
           updated_team_members,
           product_names
         )

         Phoenix.PubSub.broadcast(
           Onestack.PubSub,
           "team:#{current_user.id}",
           {:team_updated}
         )

         Phoenix.PubSub.broadcast(
           Onestack.PubSub,
           "team:#{current_user.id}",
           {:member_removed, email}
         )

         {:ok, email}

       error -> error
     end
   end)}
end

@impl true
def handle_async({:remove_member, email}, {:ok, {:ok, _email}}, socket) do
  {:noreply, put_flash(socket, :info, "Team member #{email} removed successfully")}
end

def handle_async({:remove_member, _email}, {:ok, {:error, :not_found}}, socket) do
  # Rollback: reload team members
  current_user = socket.assigns.current_user
  team_members = Teams.list_team_members_by_admin(current_user)

  {:noreply,
   socket
   |> assign(team_members: team_members)
   |> assign(num_users: calculate_num_users(team_members))
   |> put_flash(:error, "Team member not found")}
end

def handle_async({:remove_member, _email}, _result, socket) do
  current_user = socket.assigns.current_user
  team_members = Teams.list_team_members_by_admin(current_user)

  {:noreply,
   socket
   |> assign(team_members: team_members)
   |> assign(num_users: calculate_num_users(team_members))
   |> put_flash(:error, "Failed to remove team member")}
end
```

- [ ] **Step 2: Compile and verify**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/onestack_web/live/application_ui/admin_live/teams_live.ex
git commit -m "feat: optimistic member removal in teams view"
```

---

## Chunk 4: optimistic UI, onboarding and user settings

### Task 12: onboarding Stripe loading with start_async

**Files:**
- Modify: `lib/onestack_web/live/onboarding_live/onboarding_live.ex`

- [ ] **Step 1: Replace send(self(), {:create_payment_intent}) with start_async**

In `handle_event("save_product_selection", ...)` (line 103), replace:
```elixir
send(self(), {:create_payment_intent})
{:noreply, assign(socket, current_step: 3)}
```
With:
```elixir
{:noreply,
 socket
 |> assign(current_step: 3, processing_payment: true)
 |> start_async(:create_payment_intent, fn ->
   create_checkout_session(socket.assigns)
 end)}
```

- [ ] **Step 2: Extract the checkout session creation logic into a private function**

Move the HTTP call logic from `handle_info({:create_payment_intent}, ...)` into a pure function:

```elixir
defp create_checkout_session(assigns) do
  unless Onestack.stripe_enabled?() do
    {:error, "Stripe is not configured"}
  else
    with {:ok, stripe_customer} <-
           find_or_create_customer(
             assigns.current_user.email,
             assigns.current_user.first_name <> " " <> assigns.current_user.last_name
           ),
         session_params <- build_session_params(assigns, stripe_customer) do
      case HTTPoison.post(
             "https://api.stripe.com/v1/checkout/sessions",
             URI.encode_query(session_params),
             [
               {"Content-Type", "application/x-www-form-urlencoded"},
               {"Authorization",
                "Basic " <> Base.encode64("#{Application.get_env(:stripity_stripe, :api_key)}:")},
               {"Stripe-Version", "2024-04-10;custom_checkout_beta=v1"}
             ]
           ) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)["client_secret"]}

        {:ok, %HTTPoison.Response{body: body}} ->
          error_data = Jason.decode!(body)
          error_message = get_in(error_data, ["error", "message"]) || "Unknown error"
          {:error, error_message}

        {:error, error} ->
          {:error, "Connection error: #{inspect(error)}"}
      end
    end
  end
end
```

- [ ] **Step 3: Add handle_async callbacks**

```elixir
@impl true
def handle_async(:create_payment_intent, {:ok, {:ok, client_secret}}, socket) do
  {:noreply, assign(socket, client_secret: client_secret, processing_payment: false)}
end

def handle_async(:create_payment_intent, {:ok, {:error, message}}, socket) do
  {:noreply,
   socket
   |> assign(processing_payment: false)
   |> put_flash(:error, "Payment setup failed: #{message}")}
end

def handle_async(:create_payment_intent, {:exit, reason}, socket) do
  {:noreply,
   socket
   |> assign(processing_payment: false)
   |> put_flash(:error, "Payment setup failed unexpectedly: #{inspect(reason)}")}
end
```

- [ ] **Step 4: Remove the old handle_info({:create_payment_intent}, ...) callback**

Delete the entire `handle_info({:create_payment_intent}, socket)` function (lines 160-262) as it is replaced by the `start_async` + `handle_async` pattern.

- [ ] **Step 5: Compile and verify**

Run: `mix compile`
Expected: Compiles without errors.

- [ ] **Step 6: Commit**

```bash
git add lib/onestack_web/live/onboarding_live/onboarding_live.ex
git commit -m "feat: use start_async for Stripe checkout in onboarding"
```

---

### Task 13: user settings form loading states

**Files:**
- Modify: `lib/onestack_web/live/user_settings_live.ex`

- [ ] **Step 1: Verify phx-disable-with is already present on form buttons**

Check the template. The email form button already has `phx-disable-with="Sending verification..."` (line 127) and the password form button has `phx-disable-with="Updating..."` (line 218). These are correct.

- [ ] **Step 2: Add phx-disable-with to the cancel subscription button**

In the cancel subscription modal, add loading feedback to the confirmation button (around line 393):

Change:
```heex
<button
  phx-click="cancel_subscription"
  type="button"
  class="..."
>
```
To:
```heex
<button
  phx-click="cancel_subscription"
  phx-disable-with="Cancelling..."
  type="button"
  class="..."
>
```

Note: The view already has a `canceling_subscription` assign with a spinner. The `phx-disable-with` adds immediate button feedback while the existing spinner pattern handles the extended loading state.

- [ ] **Step 3: Commit**

```bash
git add lib/onestack_web/live/user_settings_live.ex
git commit -m "feat: add button loading states to user settings"
```

---

### Task 14: add global CSS loading transitions

**Files:**
- Modify: `assets/tailwind.config.js` (already has phx-click-loading and phx-submit-loading variants)

- [ ] **Step 1: Verify Tailwind variants exist**

The tailwind config already has `phx-click-loading`, `phx-submit-loading` and `phx-change-loading` variants (lines 80-97). These are correct and need no changes.

- [ ] **Step 2: Add loading utility classes to core_components.ex (optional)**

If desired, add a loading-aware button variant to `core_components.ex` that automatically applies opacity changes during loading. This is optional, as `phx-disable-with` handles most cases.

---

### Task 15: final verification

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 2: Start the dev server**

Run: `mix phx.server`
Expected: Server starts without errors. Verify key pages load:
- Landing page (localhost:4000)
- Login page (localhost:4000/users/log_in)
- Registration page (localhost:4000/users/register)

- [ ] **Step 3: Commit any final fixes**

If any fixes were needed, commit them.

- [ ] **Step 4: Create a summary commit if needed**

If no additional commits were needed, the work is complete.
