defmodule OnestackWeb.Member.FeaturesLive do
  use OnestackWeb, :live_view
  alias Onestack.{StripeCache, Teams, Accounts, Member.Stats}
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
    admin_company_name = get_admin_company_name(current_user)
    IO.inspect(stats.subscribed_products)

    # Assign all the stats we need
    socket =
      socket
      |> assign(current_user: current_user)
      |> assign(team_members: stats.team_members)
      |> assign(subscribed_products: stats.subscribed_products)
      |> assign(num_users: length(stats.team_members))
      |> assign(products: Onestack.CatalogMonthly.list_products())
      |> assign(invited_emails: [])
      |> assign(admin_company_name: admin_company_name)

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
  def handle_params(_params, uri, socket) do
    {:noreply, socket |> assign(current_path: URI.parse(uri).path)}
  end

  @impl true

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  defp get_combined_customer(email) do
    Enum.find(StripeCache.list_combined_customers(), &(&1.email == email))
  end

  defp get_admin_company_name(nil), do: nil

  defp get_admin_company_name(current_user) do
    # First check if the user is a team admin
    team = Teams.get_team_by_admin(current_user)

    if team do
      # User is an admin, return their own company name
      current_user.company_name
    else
      # User is not an admin, find the team they belong to
      team =
        Enum.find(Teams.list_teams(), fn t ->
          current_user.email in t.members
        end)

      case team do
        # User is not part of any team
        nil ->
          nil

        team ->
          # Get the admin's user profile and return their company name
          admin = Accounts.get_user_by_email(team.admin_email)
          if admin, do: admin.company_name, else: nil
      end
    end
  end

  defp usage_color(percentage) when percentage >= 0.9, do: "bg-red-500"
  defp usage_color(percentage) when percentage >= 0.7, do: "bg-amber-500"
  defp usage_color(_percentage), do: "bg-green-500"
end
