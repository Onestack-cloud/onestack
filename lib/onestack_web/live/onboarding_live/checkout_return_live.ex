defmodule OnestackWeb.CheckoutReturnLive do
  use OnestackWeb, :live_view
  require Logger
  alias Onestack.Teams

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

    # Mock selected products for test session
    mock_products = ["product1", "product2"]

    {:ok,
     socket
     |> assign(:page_title, "Checkout Successful")
     |> assign(:checkout_session, mock_session)
     |> assign(:selected_products, mock_products)}
  end

  def mount(%{"session_id" => session_id}, session, socket) do
    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end

    case fetch_checkout_session(session_id) do
      {:ok, checkout_session} ->
        # update_stripe_cache(checkout_session.customer, checkout_session.subscription)

        # Extract product IDs from metadata
        subscribed_products =
          case checkout_session.metadata["selected_products"] do
            nil ->
              []

            json_string ->
              case Jason.decode(String.downcase(json_string)) do
                {:ok, products} -> products
                _ -> []
              end
          end

        # Prepare the base socket with common assigns
        socket =
          socket
          |> assign(:page_title, "Checkout Successful")
          |> assign(:checkout_session, checkout_session)
          |> assign(:selected_products, subscribed_products)

        case Teams.get_team_by_admin(%{email: current_user.email}) do
          nil ->
            # Remember to update cache?
            Teams.get_or_create_team(%{email: current_user.email, products: subscribed_products})

            Onestack.MemberManager.add_member(
              current_user.email,
              subscribed_products
            )

            {:ok, socket}

          _existing_member ->
            # User already exists, just assign user status
            {:ok, assign(socket, :user_status, :existing)}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch checkout session: #{inspect(reason)}")

        {:ok,
         socket
         |> assign(:page_title, "Checkout Error")
         |> assign(:error, "Failed to load checkout information")}
    end
  end

  def fetch_checkout_session(session_id) do
    case Stripe.Checkout.Session.retrieve(session_id, %{expand: ["line_items"]}) do
      {:ok, checkout_session} -> {:ok, checkout_session}
      {:error, reason} -> {:error, reason}
    end
  end
end
