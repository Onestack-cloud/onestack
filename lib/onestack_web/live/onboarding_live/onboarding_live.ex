defmodule OnestackWeb.OnboardingLive do
  use OnestackWeb, :live_view

  alias Onestack.{Accounts, Teams}

  @impl true
  def mount(_params, session, socket) do
    changeset = Accounts.change_user_registration(%Accounts.User{})
    products = Onestack.CatalogMonthly.list_products()

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end

    socket =
      socket
      |> assign(
        page_title: "Onboarding",
        current_step: 2,
        total_steps: 3,
        trigger_submit: false,
        check_errors: false,
        products: products,
        # Convert products list to a map for faster lookups
        products_by_id: Map.new(products, &{&1.id, &1}),
        selected_products: [],
        selected_plan: "individual",
        num_users: 1,
        card_errors: %{},
        processing_payment: false,
        stripe_session_id: nil,
        client_secret: nil,
        current_user: current_user
      )
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("next_step", _params, %{assigns: %{current_step: current_step}} = socket)
      when current_step < 3 do
    {:noreply, assign(socket, current_step: current_step + 1)}
  end

  @impl true
  def handle_event("prev_step", _params, %{assigns: %{current_step: current_step}} = socket)
      when current_step > 1 do
    {:noreply, assign(socket, current_step: current_step - 1)}
  end

  @impl true
  def handle_event("save_registration", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        # Move to the next step after successful registration
        {:noreply,
         socket
         |> assign(current_user: user, current_step: 2)
         |> put_flash(:info, "Account created successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(check_errors: true)
         |> assign_form(changeset)}
    end
  end

  @impl true
  def handle_event("toggle_product", %{"product" => product_id}, socket) do
    # Convert product_id to integer since it comes as string from the form
    product_id = String.to_integer(product_id)

    selected_products =
      if product_id in socket.assigns.selected_products do
        List.delete(socket.assigns.selected_products, product_id)
      else
        [product_id | socket.assigns.selected_products]
      end

    {:noreply, assign(socket, :selected_products, selected_products)}
  end

  @impl true
  def handle_event("set_plan", %{"plan" => plan}, socket) do
    {:noreply, assign(socket, :selected_plan, plan)}
  end

  @impl true
  def handle_event("update_payment_form", %{"payment" => payment_params}, socket) do
    {:noreply, assign(socket, payment_form: to_form(payment_params))}
  end

  @impl true
  def handle_event("set_num_users", %{"num_users" => num_users}, socket) do
    {:noreply, assign(socket, num_users: String.to_integer(num_users))}
  end

  @impl true
  def handle_event("save_product_selection", _params, socket) do
    if Enum.empty?(socket.assigns.selected_products) do
      {:noreply,
       put_flash(socket, :error, "Please select at least one product before continuing")}
    else
      send(self(), {:create_payment_intent})
      {:noreply, assign(socket, current_step: 3)}
    end
  end

  @impl true
  def handle_event("payment-success", payment_result, socket) do
    # Extract the payment_intent ID
    payment_intent_id = payment_result["id"]

    # Confirm or update the PaymentIntent status with Stripe
    case Stripe.PaymentIntent.retrieve(payment_intent_id) do
      {:ok, payment_intent} ->
        # Create subscription records in your database
        # Associate with user, etc.
        IO.inspect(payment_intent, label: "Payment Intent")
        {:noreply, socket |> redirect(to: ~p"/dashboard")}

      {:error, error} ->
        {:noreply, socket |> put_flash(:error, "Payment verification failed: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(:payment_processed, socket) do
    # This is now handled by the Stripe webhook
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:create_payment_intent},
        socket
      ) do
    IO.puts("handle info called")

    # Calculate the actual amount in cents (multiply by 100 since Stripe uses cents)

    with {:ok, stripe_customer} <-
           find_or_create_customer(
             socket.assigns.current_user.email,
             socket.assigns.current_user.first_name <>
               " " <> socket.assigns.current_user.last_name
           ),
         # Use a single line item with quantity instead of multiple line items
         session_params <- %{
           "line_items[0][price]" =>
             case socket.assigns.selected_plan do
               "individual" -> "price_1QywRUFzZpjdOGbNhOvS4CFX"
               "team" -> "price_1QywTRFzZpjdOGbNveOtxJTF"
             end,
           "line_items[0][quantity]" => length(socket.assigns.selected_products),
           "mode" => "subscription",
           "return_url" =>
             "http://localhost:4000/checkout/return?session_id={CHECKOUT_SESSION_ID}",
           "ui_mode" => "custom",
           "customer" => stripe_customer.id,
           "metadata[selected_products]" =>
             socket.assigns.selected_products
             |> Enum.map(fn product_id ->
               product = Map.get(socket.assigns.products_by_id, product_id)
               String.downcase(product.onestack_product_name)
             end)
             |> Jason.encode!(),
           "metadata[seats]" => %{
             socket.assigns.current_user.email => {"features", socket.assigns.selected_products}
           }
         },
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.post(
             "https://api.stripe.com/v1/checkout/sessions",
             URI.encode_query(session_params),
             [
               {"Content-Type", "application/x-www-form-urlencoded"},
               {"Authorization",
                "Basic " <> Base.encode64("#{Application.get_env(:stripity_stripe, :api_key)}:")},
               {"Stripe-Version", "2024-04-10;custom_checkout_beta=v1"}
             ]
           ) do
      IO.inspect(Jason.decode!(body))

      {:noreply,
       socket
       |> assign(:client_secret, Jason.decode!(body)["client_secret"])}
    else
      {:error, error} ->
        {:noreply,
         assign(socket, :stripe_error, "There was an error with Stripe: #{inspect(error)}")}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} when status_code != 200 ->
        error_data = Jason.decode!(body)
        error_message = get_in(error_data, ["error", "message"]) || "Unknown error"

        IO.inspect(error_data, label: "Stripe API Error")

        {:noreply,
         socket
         |> assign(:stripe_error, "Stripe API Error: #{error_message}")
         |> put_flash(:error, "Payment setup failed: #{error_message}")}

      _ ->
        {:noreply, assign(socket, :stripe_error, "There was an error with Stripe")}
    end
  end

  # Find a customer by email or create a new one if not found
  def find_or_create_customer(email, full_name) do
    case Stripe.Customer.list(%{email: email}) do
      {:ok, %{data: [customer | _]}} ->
        # Customer exists, return the first one
        {:ok, customer}

      {:ok, %{data: []}} ->
        # No customer found, create a new one
        Stripe.Customer.create(%{email: email, name: full_name})

      error ->
        # Error occurred during list operation
        error
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end

  defp get_product_price(index, plan_type) do
    case plan_type do
      "individual" -> Enum.at([8, 6, 4, 2, 2, 2], index, 2)
      "team" -> Enum.at([10, 8, 6, 6, 6, 6], index, 6)
    end
  end

  defp calculate_total(selected_products, plan_type) do
    selected_products
    |> Enum.with_index()
    |> Enum.reduce(0, fn {_product_id, index}, acc ->
      acc + get_product_price(index, plan_type)
    end)
  end
end
