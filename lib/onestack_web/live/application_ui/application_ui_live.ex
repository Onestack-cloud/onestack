defmodule OnestackWeb.ApplicationUiLive do
  use OnestackWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    uri = URI.parse(socket.host_uri || "")

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end

    stats = Onestack.Stats.get_user_stats(current_user)

    view_state =
      determine_view_state(current_user, stats.subscribed_products, stats.team_members)

    host = uri.host
    is_app_subdomain = host != nil && String.starts_with?(host, "app.")

    if is_app_subdomain do
      IO.puts("is_app_subdomain")

      case view_state do
        :stack_admin ->
          {:ok, socket |> push_redirect(to: "/admin/features")}

        :stack_user ->
          {:ok, socket |> push_redirect(to: "/user/features")}

        _ ->
          {:ok, socket}
      end
    else
      {:ok, socket}
    end

    # socket =
    #   socket
    #   |> assign(products: Onestack.StripeCache.list_products())
    #   |> assign(show_modal: false)
    #   |> assign(modal_action: nil)
    #   |> assign(modal_product: nil)
    #   |> assign(updating: false)
    #   |> assign(view_to_show: view_state)
    #   |> assign(current_user: current_user)
    #   |> assign(team_members: stats.team_members)
    #   |> assign(selected_products: stats.subscription_products)
    #   |> assign(combined_customers: stats.combined_customers)
    #   |> assign(upcoming_invoice: stats.upcoming_invoice)
    #   |> assign(num_users: length(stats.team_members))

    # {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="py-8 lg:py-20 min-h-screen" id="subscribe">
      <div class="container mx-auto px-4">
        <div class="text-center">
          <h2 class="text-2xl font-bold mb-4">Redirecting...</h2>
          <p>
            Please wait while we redirect you to the appropriate page.
          </p>
        </div>
      </div>
    </section>
    """
  end

  defp determine_view_state(current_user, stripe_products, team_members) do
    cond do
      is_nil(current_user) ->
        :no_subscription

      stripe_products != [] && Enum.member?(team_members, current_user.email) ->
        :stack_admin

      stripe_products == [] && Enum.member?(team_members, current_user.email) ->
        :stack_user

      true ->
        :no_subscription
    end
  end
end
