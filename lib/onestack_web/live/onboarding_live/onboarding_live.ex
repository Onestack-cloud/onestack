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
      if Onestack.stripe_enabled?() do
        assigns = socket.assigns

        {:noreply,
         socket
         |> assign(current_step: 3, processing_payment: true)
         |> start_async(:create_payment_intent, fn ->
           create_checkout_session(assigns)
         end)}
      else
        # Without Stripe, activate products directly
        current_user = socket.assigns.current_user

        product_names =
          socket.assigns.selected_products
          |> Enum.map(fn product_id ->
            product = Map.get(socket.assigns.products_by_id, product_id)
            String.downcase(product.onestack_product_name)
          end)

        Teams.get_or_create_team(%{email: current_user.email, products: product_names})
        Onestack.MemberManager.add_member(current_user.email, product_names)

        {:noreply,
         socket
         |> put_flash(:info, "Products activated successfully!")
         |> redirect(external: OnestackWeb.URLHelper.subdomain_url("app"))}
      end
    end
  end

  @impl true
  def handle_event("payment-success", payment_result, socket) do
    unless Onestack.stripe_enabled?() do
      {:noreply, socket |> redirect(external: OnestackWeb.URLHelper.subdomain_url("app"))}
    else
      # Extract the payment_intent ID
      payment_intent_id = payment_result["id"]

      # Confirm or update the PaymentIntent status with Stripe
      case Stripe.PaymentIntent.retrieve(payment_intent_id) do
        {:ok, payment_intent} ->
          IO.inspect(payment_intent, label: "Payment Intent")
          {:noreply, socket |> redirect(external: OnestackWeb.URLHelper.subdomain_url("app"))}

        {:error, error} ->
          {:noreply, socket |> put_flash(:error, "Payment verification failed: #{inspect(error)}")}
      end
    end
  end

  @impl true
  def handle_info(:payment_processed, socket) do
    # This is now handled by the Stripe webhook
    {:noreply, socket}
  end

  @impl true
  def handle_async(:create_payment_intent, {:ok, {:ok, client_secret}}, socket) do
    {:noreply, assign(socket, client_secret: client_secret, processing_payment: false)}
  end

  def handle_async(:create_payment_intent, {:ok, {:error, message}}, socket) do
    {:noreply,
     socket
     |> assign(processing_payment: false)
     |> put_flash(:error, "Payment setup failed: #{message}")}
  end

  def handle_async(:create_payment_intent, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(processing_payment: false)
     |> put_flash(:error, "Payment setup failed unexpectedly: #{inspect(reason)}")}
  end

  defp create_checkout_session(assigns) do
    with {:ok, stripe_customer} <-
           find_or_create_customer(
             assigns.current_user.email,
             assigns.current_user.first_name <> " " <> assigns.current_user.last_name
           ),
         session_params <-
           (case assigns.selected_plan do
              "individual" ->
                %{
                  "line_items[0][price]" => System.get_env("STRIPE_INDIVIDUAL_PRICE_ID"),
                  "line_items[0][quantity]" => length(assigns.selected_products)
                }

              "team" ->
                %{
                  "line_items[0][price]" => System.get_env("STRIPE_TEAM_FEATURES_PRICE_ID"),
                  "line_items[0][quantity]" => length(assigns.selected_products),
                  "line_items[1][price]" => System.get_env("STRIPE_TEAM_SEATS_PRICE_ID"),
                  "line_items[1][quantity]" => assigns.num_users
                }
            end
            |> Map.merge(%{
              "mode" => "subscription",
              "return_url" =>
                "http://localhost:4000/checkout/return?session_id={CHECKOUT_SESSION_ID}",
              "ui_mode" => "custom",
              "customer" => stripe_customer.id,
              "metadata[selected_products]" =>
                assigns.selected_products
                |> Enum.map(fn product_id ->
                  product = Map.get(assigns.products_by_id, product_id)
                  String.downcase(product.onestack_product_name)
                end)
                |> Jason.encode!(),
              "metadata[seats]" =>
                Jason.encode!(%{
                  assigns.current_user.email => %{
                    "type" => "features",
                    "products" => assigns.selected_products
                  }
                }),
              "metadata[plan_type]" => assigns.selected_plan,
              "metadata[num_users]" => assigns.num_users
            })) do
      case HTTPoison.post(
             "https://api.stripe.com/v1/checkout/sessions",
             URI.encode_query(session_params),
             [
               {"Content-Type", "application/x-www-form-urlencoded"},
               {"Authorization",
                "Basic " <>
                  Base.encode64("#{Application.get_env(:stripity_stripe, :api_key)}:")},
               {"Stripe-Version", "2024-04-10;custom_checkout_beta=v1"}
             ]
           ) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)["client_secret"]}

        {:ok, %HTTPoison.Response{body: body}} ->
          error_data = Jason.decode!(body)
          error_message = get_in(error_data, ["error", "message"]) || "Unknown error"
          {:error, error_message}

        {:error, error} ->
          {:error, "Connection error: #{inspect(error)}"}
      end
    else
      {:error, error} -> {:error, "Customer creation failed: #{inspect(error)}"}
      _ -> {:error, "Payment setup failed. Please try again."}
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
      "team" -> 10  # Flat $10 per feature for team plans
    end
  end

  defp get_seat_price(num_users) do
    cond do
      num_users <= 5 -> 8
      num_users <= 10 -> 6  
      true -> 5
    end
  end

  defp calculate_total(selected_products, plan_type, num_users \\ 1) do
    feature_cost = case plan_type do
      "individual" ->
        selected_products
        |> Enum.with_index()
        |> Enum.reduce(0, fn {_product_id, index}, acc ->
          acc + get_product_price(index, plan_type)
        end)
      "team" ->
        length(selected_products) * get_product_price(0, plan_type)
    end
    
    seat_cost = case plan_type do
      "individual" -> 0
      "team" -> num_users * get_seat_price(num_users)
    end

    feature_cost + seat_cost
  end
end
