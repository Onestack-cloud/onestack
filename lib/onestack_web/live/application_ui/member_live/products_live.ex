# lib/onestack_web/live/admin/products_live.ex
defmodule OnestackWeb.Member.ProductsLive do
  use OnestackWeb, :live_view
  alias Onestack.{StripeCache, Teams, Accounts, Stats}
  import Phoenix.Component
  use OnestackWeb.AssignCurrentPath

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
      |> assign(selected_products: stats.stripe_product_ids)
      |> assign(combined_customers: stats.combined_customers)
      |> assign(upcoming_invoice: stats.upcoming_invoice)
      |> assign(num_users: length(stats.team_members))
      |> assign(products: StripeCache.list_products())
      |> assign(invited_emails: [])

    # IO.inspect(socket)

    {:ok,
     assign(socket,
       page_title: "Products",
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
    metadata = Onestack.CatalogMonthly.ProductMetadata.get_metadata(product.name)

    if metadata && metadata.closed_source_user_price do
      # Calculate closed source cost (converting from dollars to cents)
      closed_source_cost =
        metadata.closed_source_user_price
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
  def handle_event("open_modal", %{"product" => product_id, "action" => action}, socket) do
    product = Enum.find(socket.assigns.products, &(&1.id == product_id))

    if product do
      metadata = Onestack.CatalogMonthly.ProductMetadata.get_metadata(product.name)

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
  def handle_event("update_subscription", %{"action" => action, "product" => product_id}, socket) do
    current_user = socket.assigns.current_user
    current_products = socket.assigns.selected_products

    combined_customer =
      Enum.find(socket.assigns.combined_customers, &(&1.email == current_user.email))

    cond do
      action == "remove" and length(current_products) == 1 and
          hd(current_products) == product_id ->
        # This is the last product and we're removing it -> cancel subscription
        send(self(), {:cancel_subscription})
        product = Enum.find(StripeCache.list_products(), &(&1.id == product_id))
        product_name = product && product.name
        team_members = Teams.list_team_members(%{email: socket.assigns.current_user.email})

        Enum.each(team_members, fn member ->
          Onestack.MemberManager.remove_member(member, [product_name])
        end)

        Teams.delete_team(Teams.get_team_by_admin(%{email: socket.assigns.current_user.email}))

        {:noreply, assign(socket, updating: true)}

      true ->
        # Otherwise, proceed with the update as before
        send(self(), {:run_update_subscription, action, product_id})
        {:noreply, assign(socket, updating: true)}
    end
  end

  @impl true
  def handle_info({:run_update_subscription, action, product_id}, socket) do
    current_user = socket.assigns.current_user
    combined_customer = get_combined_customer(current_user.email)

    if combined_customer do
      case update_subscription(
             combined_customer.subscription_id,
             action,
             product_id,
             socket.assigns.num_users
           ) do
        {:ok, _updated_subscription} ->
          # Update the cache
          Onestack.StripeCache.update_cache_for_subscription(combined_customer.subscription_id)

          # Get fresh stats to update all subscription-related data
          stats = Stats.get_user_stats(current_user)

          action_text = if action == "add", do: "added to", else: "removed from"
          Process.send_after(self(), :clear_flash, 3000)

          {:noreply,
           socket
           |> assign(updating: false)
           |> assign(show_modal: false)
           |> assign(modal_product: nil)
           |> assign(modal_action: nil)
           |> assign(selected_products: stats.stripe_product_ids)
           |> assign(combined_customers: stats.combined_customers)
           |> assign(upcoming_invoice: stats.upcoming_invoice)
           |> assign(team_members: stats.team_members)
           |> assign(num_users: length(stats.team_members))
           |> put_flash(:info, "Product #{action_text} subscription successfully")}

        {:error, :price_not_found} ->
          {:noreply,
           socket
           |> assign(updating: false)
           |> put_flash(:error, "Could not find price for the product")}

        {:error, :item_not_found} ->
          {:noreply,
           socket
           |> assign(updating: false)
           |> put_flash(:error, "Product not found in subscription")}

        {:error, %Stripe.Error{} = error} ->
          {:noreply,
           socket
           |> assign(updating: false)
           |> put_flash(:error, "Failed to update subscription: #{error.message}")}

        _ ->
          {:noreply,
           socket
           |> assign(updating: false)
           |> put_flash(:error, "Failed to update subscription")}
      end
    else
      {:noreply,
       socket
       |> assign(updating: false)
       |> put_flash(:error, "No active subscription found")}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, socket |> assign(current_path: URI.parse(uri).path)}
  end

  @impl true
  def handle_info({:cancel_subscription}, socket) do
    current_user = socket.assigns.current_user
    combined_customer = get_combined_customer(current_user.email)

    case cancel_subscription(combined_customer.subscription_id) do
      {:ok, _canceled_subscription} ->
        {:noreply,
         socket
         |> assign(updating: false)
         |> assign(show_modal: false)
         |> assign(modal_product: nil)
         |> assign(modal_action: nil)
         |> assign(selected_products: [])}

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

  defp get_combined_customer(email) do
    Enum.find(StripeCache.list_combined_customers(), &(&1.email == email))
  end

  defp cancel_subscription(subscription_id) do
  end

  defp update_subscription(subscription_id, action, product_id, num_users) do
    {:ok, subscription} = Stripe.Subscription.retrieve(subscription_id)
    current_items = subscription.items.data
    quantity = ceil(num_users / 10)

    case action do
      "add" ->
        # Find the price for the product
        case find_price_for_product(product_id) do
          nil ->
            {:error, :price_not_found}

          price_id ->
            # Add the new item
            Stripe.Subscription.update(subscription_id, %{
              items: [
                %{
                  price: price_id,
                  quantity: quantity
                }
                | Enum.map(current_items, fn item ->
                    %{id: item.id, quantity: quantity}
                  end)
              ],
              proration_behavior: "create_prorations"
            })
        end

      "remove" ->
        # Find the item to remove
        case Enum.find(current_items, &(&1.price.product == product_id)) do
          nil ->
            {:error, :item_not_found}

          item ->
            # Remove the item
            Stripe.Subscription.update(subscription_id, %{
              items: [
                %{id: item.id, deleted: true}
                | Enum.map(Enum.reject(current_items, &(&1.id == item.id)), fn item ->
                    %{id: item.id, quantity: quantity}
                  end)
              ],
              proration_behavior: "create_prorations"
            })
        end

      _ ->
        {:error, :invalid_action}
    end
  end

  defp usage_color(percentage) when percentage >= 0.9, do: "bg-red-500"
  defp usage_color(percentage) when percentage >= 0.7, do: "bg-amber-500"
  defp usage_color(_percentage), do: "bg-green-500"
end
