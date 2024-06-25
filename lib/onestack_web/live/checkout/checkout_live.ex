defmodule OnestackWeb.CheckoutLive do
  use OnestackWeb, :live_view
  require Logger
  alias Onestack.{Payments, StripeCache}

  @impl true
  def mount(_params, session, socket) do
    current_user = Onestack.Accounts.get_user_by_session_token(session["user_token"])

    socket =
      socket
      |> assign(products: StripeCache.list_products())
      |> assign(selected_products: [])
      |> assign(num_users: 1)
      |> assign(current_user: current_user)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Onestack Checkout")
  end

  @impl true
  def handle_event("checkout", %{"id" => id}, socket) do
    send(self(), {:create_payment_intent, id: id})

    {:noreply, socket}
  end

  def handle_event("select_product", %{"product" => product_id}, socket) do
    selected_products = socket.assigns.selected_products

    updated_products =
      if product_id in selected_products do
        List.delete(selected_products, product_id)
      else
        [product_id | selected_products]
      end

    {:noreply, assign(socket, selected_products: updated_products)}
  end

  def handle_event("change", %{"_target" => ["num_users"], "num_users" => value}, socket) do
    {:noreply, assign(socket, num_users: String.to_integer(value))}
  end

  def handle_event("subscribe", _params, socket) do
    case create_checkout_session(socket.assigns) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: to_string(session.url))}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe error: #{inspect(error)}")

        {:noreply,
         put_flash(socket, :warning, "Failed to create checkout session: #{error.message}")}

      {:error, "No products selected"} ->
        {:noreply,
         put_flash(socket, :error, "Please select at least one product before subscribing")}

      {:error, reason} ->
        Logger.error("Unknown error: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "An unexpected error occurred")}
    end
  end

  defp create_checkout_session(assigns) do
    if Enum.empty?(assigns.selected_products) do
      {:error, "No products selected"}
    else
      line_items =
        Enum.map(assigns.selected_products, fn price_id ->
          quantity = if assigns.num_users > 10, do: 2, else: 1

          %{
            price: price_id,
            quantity: quantity
          }
        end)

      Stripe.Checkout.Session.create(%{
        payment_method_types: [:card],
        line_items: line_items,
        mode: :subscription,
        success_url: "https://onestack.cloud/checkout/success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "https://onestack.cloud/checkout",
        allow_promotion_codes: true,
        billing_address_collection: :required,
        payment_method_collection: :always
      })
    end
  end
end
