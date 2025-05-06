# lib/onestack_web/live/admin/products_live.ex
defmodule OnestackWeb.Admin.FeaturesLive do
  use OnestackWeb, :live_view
  alias Onestack.{StripeCache, Teams, Accounts, Admin.Stats}
  import Phoenix.Component
  use OnestackWeb.AssignCurrentPath
  require Logger

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      # Subscribe to product updates
    end

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Accounts.get_user_by_session_token(user_token)
      end

    stats = Stats.get_user_stats(current_user)

    # Assign all the stats we need
    socket =
      socket
      |> assign(current_user: current_user)
      |> assign(team_members: stats.team_members)
      |> assign(selected_product_names: stats.subscribed_product_names)
      |> assign(combined_customers: stats.combined_customers)
      |> assign(upcoming_invoice: stats.upcoming_invoice)
      |> assign(num_users: length(stats.team_members))
      |> assign(products: Onestack.CatalogMonthly.list_products())
      |> assign(invited_emails: [])

    # IO.inspect(socket)

    {:ok,
     assign(socket,
       page_title: "Features",
       selected_category: "all",
       search: "",
       show_product_details: nil,
       total_monthly_savings: "$3,450",
       total_monthly_cost: "$899",
       show_onboarding: false,
       selected_view: "grid",
       show_compare: false,
       current_tab: "active",
       show_modal: false,
       modal_product: nil,
       modal_action: nil,
       updating: false
     )}
  end

  def find_price_for_product(product_id) do
    Enum.find_value(StripeCache.list_products(), fn product ->
      if product.id == product_id, do: product.default_price
    end)
  end

  defp calculate_monthly_savings(product, num_users, upcoming_invoice) do
    # Get product metadata for closed source pricing

    if product && product.closed_source_user_price do
      # Calculate closed source cost (converting from dollars to cents)
      closed_source_cost =
        product.closed_source_user_price
        |> Decimal.mult(Decimal.new(num_users))
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      # Get the actual subscription cost for this product
      subscription_cost =
        case upcoming_invoice do
          %{subscription: subscription_id} ->
            StripeCache.get_subscription_item_price(subscription_id, product.id) || 0

          _ ->
            0
        end

      # Calculate savings (closed source cost - our subscription cost)
      Money.new(closed_source_cost - subscription_cost)
    else
      Money.new(0)
    end
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  @impl true
  def handle_event(
        "open_modal",
        %{"product" => product_name, "action" => action, "value" => _value},
        socket
      ) do
    product =
      Enum.find(
        socket.assigns.products,
        &(String.downcase(&1.onestack_product_name) == String.downcase(product_name))
      )

    if product do
      metadata = Onestack.CatalogMonthly.ProductMetadata.get_metadata(product_name)

      {:noreply,
       assign(socket,
         show_modal: true,
         modal_action: action,
         modal_product: product,
         product_metadata: metadata
       )}
    else
      {:noreply, put_flash(socket, :error, "Product not found")}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, show_modal: false, modal_action: nil, modal_product: nil)}
  end

  @impl true
  def handle_event(
        "update_subscription",
        %{"action" => action, "product" => onestack_product_name, "value" => _value},
        socket
      ) do
    current_products = socket.assigns.selected_product_names
    onestack_product_name = String.downcase(onestack_product_name)

    case {action, current_products} do
      {"remove", [only_product]} when only_product == onestack_product_name ->
        # This is the last product and we're removing it -> cancel subscription
        active_subscription_id =
          find_customer_with_active_subscription(socket.assigns.current_user.email)

        send(self(), {:cancel_subscription, active_subscription_id})

        # Remove member from team and delete team
        current_user = socket.assigns.current_user
        team_member_emails = Teams.list_team_members_by_admin(%{email: current_user.email})

        Enum.each(team_member_emails, fn email ->
          Onestack.MemberManager.remove_member_from_product(email, onestack_product_name)
        end)

        Teams.delete_team(Teams.get_team_by_admin(%{email: current_user.email}))

        {:noreply, assign(socket, updating: true)}

      _ ->
        # Otherwise, proceed with the update
        # Log that the product is being added to the stack

        Logger.info("Product #{onestack_product_name} is being #{action}ed to the stack")

        send(self(), {:run_update_subscription, action, onestack_product_name})
        {:noreply, assign(socket, updating: true)}
    end
  end

  @impl true
  def handle_info({:run_update_subscription, action, onestack_product_name}, socket) do
    current_user = socket.assigns.current_user
    Logger.info("Starting subscription update for action: #{action}, product: #{onestack_product_name}")

    result = find_customer_with_active_subscription(current_user.email)
    Logger.info("Customer subscription lookup result: #{inspect(result)}")

    case result do
      {:ok, subscription_id} ->
        Logger.info("Found active subscription: #{subscription_id}, proceeding with update")
        handle_subscription_update(subscription_id, action, onestack_product_name, socket)

      {:error, reason} ->
        Logger.error("Subscription update failed with reason: #{inspect(reason)}")
        {:noreply,
         socket
         |> assign(updating: false)
         |> put_flash(:error, error_message_for(reason))}
    end
  end

  defp find_customer_with_active_subscription(email) do
    Logger.info("Looking for customer with email: #{email}")
    case Stripe.Customer.list(%{email: email}) do
      {:ok, %{data: []}} ->
        Logger.info("No customer found for email: #{email}")
        {:error, :no_customer}

      {:ok, %{data: customers}} ->
        Logger.info("Found #{length(customers)} customers for email: #{email}")
        find_active_subscription(customers)

      {:error, error} ->
        Logger.error("Stripe error when listing customers: #{inspect(error)}")
        {:error, error}
    end
  end

  defp find_active_subscription(customers) do
    Logger.info("Searching for active subscriptions among #{length(customers)} customers")
    # Try to find a customer with an active subscription
    Enum.reduce_while(customers, {:error, :no_subscription}, fn customer, acc ->
      Logger.info("Checking subscriptions for customer: #{customer.id}")
      case Stripe.Subscription.list(%{customer: customer.id, status: "active", limit: 1}) do
        {:ok, %{data: [subscription | _]}} ->
          Logger.info("Found active subscription #{subscription.id} for customer #{customer.id}")
          {:halt, {:ok, subscription.id}}

        {:ok, %{data: []}} ->
          Logger.info("No active subscriptions found for customer #{customer.id}")
          {:cont, acc}

        {:error, error} ->
          Logger.error("Error listing subscriptions for customer #{customer.id}: #{inspect(error)}")
          {:cont, acc}
      end
    end)
  end

  defp handle_subscription_update(subscription_id, action, onestack_product_name, socket) do
    Logger.info("Handling subscription update for subscription #{subscription_id}, action: #{action}, product: #{onestack_product_name}")
    case update_subscription_with_product(
           subscription_id,
           action,
           onestack_product_name,
           socket
         ) do
      {:ok, updated_subscription} ->
        Logger.info("Successfully updated subscription: #{updated_subscription.id}")
        # Get fresh stats to update all subscription-related data
        stats = Stats.get_user_stats(socket.assigns.current_user)
        action_text = if action == "add", do: "added to", else: "removed from"
        Process.send_after(self(), :clear_flash, 3000)

        {:noreply,
         socket
         |> assign(updating: false)
         |> assign(show_modal: false)
         |> assign(modal_product: nil)
         |> assign(modal_action: nil)
         |> assign(selected_product_names: stats.subscribed_product_names)
         |> assign(combined_customers: stats.combined_customers)
         |> assign(upcoming_invoice: stats.upcoming_invoice)
         |> assign(team_members: stats.team_members)
         |> assign(num_users: length(stats.team_members))
         |> put_flash(:info, "Product #{action_text} subscription successfully")}

      {:error, reason} ->
        Logger.error("Failed to update subscription with reason: #{inspect(reason)}")
        {:noreply,
         socket
         |> assign(updating: false)
         |> put_flash(:error, error_message_for(reason))}
    end
  end

  defp update_subscription_with_product(subscription_id, action, onestack_product_name, socket) do
    Logger.info("Updating subscription #{subscription_id} with product change (#{action}: #{onestack_product_name})")
    with {:ok, subscription} <- Stripe.Subscription.retrieve(subscription_id),
         _ <- Logger.info("Retrieved subscription: #{inspect(subscription.id)}"),
         {:ok, new_price} <- create_new_price_for_subscription(subscription, action, socket),
         _ <- Logger.info("Created new price: #{inspect(new_price.id)}"),
         {:ok, updated_subscription} <- update_subscription_with_price(subscription, new_price) do
      # Update team products
      team_member_emails = Teams.list_team_members_by_admin(socket.assigns.current_user)

      case action do
        "add" ->
          add_product_to_team(onestack_product_name, socket.assigns.current_user)

          Enum.each(team_member_emails, fn email ->
            Onestack.MemberManager.add_member_to_product(email, onestack_product_name)
          end)

        "remove" ->
          remove_product_from_team(onestack_product_name, socket.assigns.current_user)

          Enum.each(team_member_emails, fn email ->
            Onestack.MemberManager.remove_member_from_product(email, onestack_product_name)
          end)
      end

      {:ok, updated_subscription}
    else
      {:error, reason} = error ->
        Logger.error("Failed in update_subscription_with_product: #{inspect(reason)}")
        error
    end
  end

  defp create_new_price_for_subscription(subscription, action, socket) do
    # Get current products count and calculate new count
    current_items = subscription.items.data
    current_product_count = length(current_items)

    new_product_count =
      case action do
        "add" -> current_product_count + 1
        "remove" -> current_product_count - 1
        _ -> current_product_count
      end

    # Determine plan type based on number of users
    plan_type = if socket.assigns.num_users > 1, do: "team", else: "individual"

    # Calculate new price using graduated pricing
    new_price_dollars =
      Onestack.CatalogMonthly.calculate_subscription_price(new_product_count, plan_type) *
        socket.assigns.num_users

    # Convert to cents for Stripe
    new_price_cents = new_price_dollars * 100

    # Get subscription item and product ID
    subscription_item = List.first(subscription.items.data)
    product_id = subscription_item.price.product

    # Get the currency from the existing subscription
    currency = subscription_item.price.currency

    # Create new price
    price_params = %{
      unit_amount: new_price_cents,
      currency: currency,
      recurring: %{
        interval: "month"
      },
      product: product_id,
      lookup_key: "custom_#{subscription.id}_#{System.system_time(:second)}"
    }

    Stripe.Price.create(price_params)
  end

  defp update_subscription_with_price(subscription, price) do
    subscription_item_id = List.first(subscription.items.data).id

    update_params = %{
      items: [
        %{
          id: subscription_item_id,
          price: price.id
        }
      ],
      metadata:
        Map.merge(subscription.metadata || %{}, %{
          "custom_price_updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }),
      proration_behavior: "create_prorations"
    }

    Stripe.Subscription.update(subscription.id, update_params)
  end

  defp add_product_to_team(onestack_product_name, current_user) do
    team = Teams.get_team_by_admin(%{email: current_user.email})
    updated_products = [onestack_product_name | team.products] |> Enum.uniq()
    Teams.update_team(team, %{products: updated_products})
  end

  defp remove_product_from_team(onestack_product_name, current_user) do
    team = Teams.get_team_by_admin(%{email: current_user.email})
    updated_products = Enum.reject(team.products, &(&1 == onestack_product_name))
    Teams.update_team(team, %{products: updated_products})
  end

  defp error_message_for(reason) do
    case reason do
      :no_customer -> "No Stripe customer found for this user"
      :no_subscription -> "No active subscription found for any customer with this email"
      :price_not_found -> "Could not find price for the product"
      :item_not_found -> "Product not found in subscription"
      %Stripe.Error{} = error -> "Failed to update subscription: #{error.message}"
      _ -> "Failed to update subscription"
    end
  end

  @impl true
  def handle_info({:cancel_subscription, subscription_id}, socket) do
    case Stripe.Subscription.cancel(subscription_id) do
      {:ok, _canceled_subscription} ->
        {:noreply,
         socket
         |> assign(updating: false)
         |> assign(show_modal: false)
         |> assign(modal_product: nil)
         |> assign(modal_action: nil)
         |> assign(selected_product_names: [])}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(updating: false)
         |> put_flash(:error, "Failed to cancel subscription")}
    end
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  defp usage_color(percentage) when percentage >= 0.9, do: "bg-red-500"
  defp usage_color(percentage) when percentage >= 0.7, do: "bg-amber-500"
  defp usage_color(_percentage), do: "bg-green-500"
end
