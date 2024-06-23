defmodule OnestackWeb.SuccessLive do
  use OnestackWeb, :live_view
  require Logger

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
    case fetch_checkout_session(session_id) do
      {:ok, checkout_session} ->
        {:ok,
         socket
         |> assign(:page_title, "Checkout Successful")
         |> assign(:checkout_session, checkout_session)}

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

  def render(%{checkout_session: checkout_session} = assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Thank You for Your Purchase!</h1>
      <div class="alert alert-success mb-6">
        <div class="flex">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            class="w-6 h-6 mx-2 stroke-current"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            >
            </path>
          </svg>
          <label>Your payment has been processed successfully.</label>
        </div>
      </div>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Order Summary</h2>
          <div class="overflow-x-auto">
            <table class="table w-full">
              <tbody>
                <tr>
                  <td class="font-bold">Order ID</td>
                  <td><%= checkout_session.id %></td>
                </tr>
                <tr>
                  <td class="font-bold">Total Amount</td>
                  <td>
                    <%= Money.to_string(Money.new(checkout_session.amount_total)) %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <h3 class="text-xl font-semibold mt-4 mb-2">Products</h3>
          <div class="overflow-x-auto">
            <table class="table w-full">
              <thead>
                <tr>
                  <th>Description</th>
                  <th>Amount</th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- checkout_session.line_items.data do %>
                  <tr>
                    <td><%= item.description %></td>
                    <td>
                      <%= Money.to_string(Money.new(item.amount_total)) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      <div class="mt-8">
        <a href="/" class="btn btn-primary">Return to Home</a>
      </div>
    </div>
    """
  end

  def render(%{error: error_message} = assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Checkout Error</h1>
      <div class="alert alert-error">
        <div class="flex-1">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            class="w-6 h-6 mx-2 stroke-current"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"
            >
            </path>
          </svg>
          <label><%= error_message %></label>
        </div>
      </div>
      <div class="mt-8">
        <a href="/" class="btn btn-primary">Return to Home</a>
      </div>
    </div>
    """
  end
end
