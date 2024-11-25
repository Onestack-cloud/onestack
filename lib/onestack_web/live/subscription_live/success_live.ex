defmodule OnestackWeb.SuccessLive do
  use OnestackWeb, :live_view
  require Logger
  alias Onestack.{Teams, StripeCache}
  alias OnestackWeb.SubscribeLive

  def mount(%{"session_id" => "test_session"}, _session, socket) do
    mock_session = %{
      id: "test_session",
      amount_total: 2000,
      line_items: %{
        data: [
          %{description: "Test Product 1", amount_total: 1000},
          %{description: "Test Product 2", amount_total: 1000}
        ]
      }
    }

    {:ok,
     socket
     |> assign(:page_title, "Checkout Successful")
     |> assign(:checkout_session, mock_session)}
  end

  def mount(%{"session_id" => session_id}, _session, socket) do
    # current_user = get_current_user(session)

    case fetch_checkout_session(session_id) do
      {:ok, checkout_session} ->
        update_stripe_cache(checkout_session.customer, checkout_session.subscription)
        customer_email = checkout_session.customer_details.email

        case Teams.get_team_by_admin(%{email: customer_email}) do
          nil ->
            combined_customer =
              StripeCache.list_combined_customers()
              |> Enum.find(fn customer -> customer.email == customer_email end)

            product_names =
              SubscribeLive.get_product_names(combined_customer.products)
              |> Enum.map(&String.downcase/1)

            IO.inspect(product_names)

            # Remember to update cache?
            Teams.get_or_create_team(%{email: customer_email, products: product_names})

            Onestack.MemberManager.add_member(
              customer_email,
              product_names
            )

            {:ok,
             socket
             |> assign(:page_title, "Checkout Successful")
             |> assign(:checkout_session, checkout_session)}

          _existing_member ->
            # User already exists, just assign the checkout session
            {:ok,
             socket
             |> assign(:page_title, "Checkout Successful")
             |> assign(:checkout_session, checkout_session)
             |> assign(:user_status, :existing)}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch checkout session: #{inspect(reason)}")

        {:ok,
         socket
         |> assign(:page_title, "Checkout Error")
         |> assign(:error, "Failed to load checkout information")}
    end
  end

  defp fetch_checkout_session(session_id) do
    Stripe.Checkout.Session.retrieve(session_id, expand: ["line_items"])
  end

  defp update_stripe_cache(customer_id, subscription_id) do
    Onestack.StripeCache.update_cache_for_new_customer(customer_id)
    Onestack.StripeCache.update_cache_for_subscription(subscription_id)
  end
end
