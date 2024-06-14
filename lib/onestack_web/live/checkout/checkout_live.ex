defmodule OnestackWeb.CheckoutLive do
  use OnestackWeb, :live_view

  alias Onestack.{Payments, StripeCache}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(products: StripeCache.list_products())
      |> assign(selected_products: [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Stripe Checkout example")
    |> assign(:items, ["Alpha", "Bravo", "Charlie"])
  end

  @impl true
  def handle_event("checkout", %{"id" => id}, socket) do
    send(self(), {:create_payment_intent, id: id})

    {:noreply, socket}
  end

  def handle_event("select_product", %{"product" => product_name}, socket) do
    selected_products = Map.get(socket.assigns, :selected_products, [])

    new_selected_products =
      if Enum.member?(selected_products, product_name) do
        List.delete(selected_products, product_name)
      else
        [product_name | selected_products]
      end

    {:noreply, assign(socket, :selected_products, new_selected_products)}
  end

  @impl true
  def handle_info({:create_payment_intent, id: id}, socket) do
    # replace with your price ID
    {:ok, price_id} = StripeCache.get_price_id("cal_monthly")
    # replace with your tax rate ID
    {:ok, tax_id} = StripeCache.get_tax_rate_id("AU")
    url = OnestackWeb.Endpoint.url()

    create_params = %{
      cancel_url: url,
      success_url: url,
      payment_method_types: ["card"],
      mode: "subscription",
      metadata: [name: id],
      line_items: [
        %{
          price: price_id,
          quantity: 1,
          tax_rates: [tax_id]
        }
      ]
    }

    case Stripe.Checkout.Session.create(create_params) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, error} ->
        IO.inspect(error)
        {:noreply, socket}
    end
  end
end
