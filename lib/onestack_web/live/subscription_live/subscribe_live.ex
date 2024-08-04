defmodule OnestackWeb.SubscribeLive do
  use OnestackWeb, :live_view
  require Logger
  alias Onestack.{StripeCache, Teams, Accounts}

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Accounts.get_user_by_session_token(user_token)
      end

    combined_customers = Onestack.StripeCache.list_combined_customers()

    user_products =
      if current_user do
        case Enum.find(combined_customers, fn customer -> customer.email == current_user.email end) do
          nil -> []
          customer -> customer.products
        end
      else
        []
      end

    team_members =
      if current_user do
        Teams.list_team_members(current_user)
      else
        []
      end

    num_users = calculate_num_users(current_user, team_members)

    has_subscription = user_products != []
    IO.inspect(current_user)

    socket =
      socket
      |> assign(products: StripeCache.list_products())
      |> assign(selected_products: user_products)
      |> assign(num_users: num_users)
      |> assign(current_user: current_user)
      |> assign(team_members: team_members)
      |> assign(show_modal: false)
      |> assign(modal_action: nil)
      |> assign(modal_product: nil)
      |> assign(updating: false)
      |> assign(has_subscription: has_subscription)

    {:ok, socket}
  end

  defp calculate_num_users(current_user, team_members) do
    if current_user do
      # Include the current user
      length(team_members)
    else
      1
    end
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

  def handle_event("change", %{"_target" => ["num_users"]} = params, socket) do
    case params do
      %{"num_users" => value} when value != "" ->
        {:noreply, assign(socket, num_users: String.to_integer(value))}

      _ ->
        # or whatever default value you want
        {:noreply, assign(socket, num_users: 1)}
    end
  end

  def handle_event("subscribe", _params, socket) do
    case create_checkout_session(socket) do
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

  def handle_event("add_member", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user
    combined_customer = get_combined_customer(current_user.email)

    if valid_email?(email) do
      case Teams.add_team_member(current_user, email, combined_customer.products) do
        {:ok, _team} ->
          product_names =
            get_product_names(
              socket.assigns.selected_products,
              StripeCache.list_products()
            )

          {:ok, job_id} =
            Onestack.MemberManager.add_member(
              email,
              product_names
            )

          IO.inspect(job_id)
          updated_team_members = Teams.list_team_members(current_user)

          {:noreply,
           socket
           |> assign(team_members: updated_team_members)
           |> assign(num_users: calculate_num_users(current_user, updated_team_members))
           |> put_flash(:info, "Team member added successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to add team member")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid email address")}
    end
  end

  def handle_event("remove_member", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user

    case Teams.remove_team_member(current_user, email) do
      {:ok, _team} ->
        product_names =
          get_product_names(
            socket.assigns.selected_products,
            StripeCache.list_products()
          )

        Onestack.MemberManager.remove_member(
          email,
          product_names
        )

        updated_team_members = Teams.list_team_members(current_user)

        {:noreply,
         socket
         |> assign(team_members: Teams.list_team_members(current_user))
         |> assign(num_users: calculate_num_users(current_user, updated_team_members))
         |> put_flash(:info, "Team member removed successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Team member not found")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove team member")}
    end
  end

  def handle_event("update_subscription", %{"action" => action, "product" => product_id}, socket) do
    current_products = socket.assigns.selected_products

    cond do
      action == "remove" and length(current_products) == 1 and
          hd(current_products) == product_id ->
        # This is the last product and we're removing it, so cancel the subscription
        send(self(), {:cancel_subscription})
        product = Enum.find(StripeCache.list_products(), &(&1.id == product_id))
        product_name = product && product.name
        team_members = Teams.list_team_members(%{email: socket.assigns.current_user.email})

        Enum.each(team_members, fn member ->
          Onestack.MemberManager.remove_member(member, [product_name])
        end)

        {:noreply, assign(socket, updating: true)}

      true ->
        # Otherwise, proceed with the update as before
        send(self(), {:run_update_subscription, action, product_id})
        {:noreply, assign(socket, updating: true)}
    end
  end

  def handle_event("open_modal", %{"product" => product_id, "action" => action}, socket) do
    product = Enum.find(socket.assigns.products, &(&1.id == product_id))

    if product do
      {:noreply, assign(socket, show_modal: true, modal_action: action, modal_product: product)}
    else
      {:noreply, put_flash(socket, :error, "Product not found")}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, show_modal: false, modal_action: nil, modal_product: nil)}
  end

  def get_product_names(product_ids, products) do
    product_map =
      Enum.reduce(products, %{}, fn product, acc ->
        Map.put(acc, product.id, String.downcase(product.name))
      end)

    Enum.map(product_ids, fn id ->
      Map.get(product_map, id, "unknown product")
    end)
  end

  @impl true
  def handle_info({:run_update_subscription, action, product_id}, socket) do
    current_user = socket.assigns.current_user
    combined_customer = get_combined_customer(current_user.email)
    num_users = socket.assigns.num_users

    case update_subscription(combined_customer.subscription_id, action, product_id, num_users) do
      {:ok, %Stripe.SubscriptionItem{} = _updated_item} ->
        # Update the cache
        Onestack.StripeCache.update_cache_for_subscription(combined_customer.subscription_id)
        # Fetch the updated subscription to get the full list of products
        {:ok, updated_subscription} =
          Stripe.Subscription.retrieve(combined_customer.subscription_id)

        updated_products = extract_product_ids(updated_subscription)
        # Merge updated_products with existing selected_products
        # new_selected_products = merge_products(socket.assigns.selected_products, updated_products)

        action_text = if action == "add", do: "added to", else: "removed from"
        Process.send_after(self(), :clear_flash, 3000)

        {
          :noreply,
          socket
          |> assign(
            selected_products: updated_products,
            show_modal: false,
            modal_action: nil,
            modal_product: nil,
            updating: false
          )
          |> put_flash(:info, "Product #{action_text} subscription successfully")
        }

      {:error, :item_not_found} ->
        {:noreply, put_flash(socket, :error, "Product not found in the subscription")}

      {:error, :price_not_found} ->
        {:noreply, put_flash(socket, :error, "Price not found for the given product")}

      {:error, :invalid_action} ->
        {:noreply, put_flash(socket, :error, "Invalid action specified")}

      {:error, %Stripe.Error{} = error} ->
        {:noreply, put_flash(socket, :error, "Failed to update subscription: #{error.message}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "An unexpected error occurred")}
    end
  end

  def handle_info({:cancel_subscription}, socket) do
    current_user = socket.assigns.current_user
    combined_customer = get_combined_customer(current_user.email)

    case cancel_subscription(combined_customer.subscription_id) do
      {:ok, _cancelled_subscription} ->
        Onestack.StripeCache.update_cache_for_subscription(combined_customer.subscription_id)
        Process.send_after(self(), :clear_flash, 3000)

        {:noreply,
         socket
         |> assign(
           updating: false,
           show_modal: false,
           modal_action: nil,
           modal_product: nil,
           selected_products: [],
           has_subscription: false
         )
         |> put_flash(:info, "Subscription cancelled successfully.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(updating: false)
         |> put_flash(:error, "Failed to cancel subscription: #{reason}")}
    end
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket, :info)}
  end

  defp cancel_subscription(subscription_id) do
    Stripe.Subscription.cancel(subscription_id)
  end

  defp update_subscription(subscription_id, action, product_id, num_users) do
    {:ok, subscription} = Stripe.Subscription.retrieve(subscription_id)
    current_items = subscription.items.data
    quantity = ceil(num_users / 10)

    admin_email =
      Enum.find_value(StripeCache.list_combined_customers(), fn customer ->
        if customer.subscription_id == subscription_id, do: customer.email
      end)

    team_members = Teams.list_team_members(%{email: admin_email})

    case action do
      "add" ->
        price_id = find_price_for_product(product_id)

        if price_id do
          params = %{
            subscription: subscription_id,
            price: price_id,
            quantity: quantity,
            proration_behavior: :create_prorations
          }

          {:ok, subscription_item} = Stripe.SubscriptionItem.create(params)

          product = Enum.find(StripeCache.list_products(), &(&1.id == product_id))
          product_name = product && product.name

          Enum.each(team_members, fn member ->
            Onestack.MemberManager.add_member(member, [product_name])
          end)

          {:ok, subscription_item}
        else
          {:error, :price_not_found}
        end

      "remove" ->
        subscription_item = Enum.find(current_items, &(&1.price.product == product_id))

        if subscription_item do
          Stripe.SubscriptionItem.delete(subscription_item.id)

          product = Enum.find(StripeCache.list_products(), &(&1.id == product_id))
          product_name = product && product.name

          Enum.each(team_members, fn member ->
            Onestack.MemberManager.remove_member(member, [product_name])
          end)

          {:ok, subscription_item}
        else
          {:error, :item_not_found}
        end

      _ ->
        {:error, :invalid_action}
    end
  end

  def find_price_for_product(product_id) do
    Enum.find_value(StripeCache.list_products(), fn product ->
      if product.id == product_id, do: product.default_price
    end)
  end

  def extract_product_ids(subscription) do
    Enum.map(subscription.items.data, & &1.plan.product)
  end

  defp get_combined_customer(email) do
    StripeCache.list_combined_customers()
    |> Enum.find(fn customer -> customer.email == email end)
  end

  defp valid_email?(email) do
    # Basic email validation regex
    email =~ ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$/
  end

  defp create_checkout_session(socket) do
    if Enum.empty?(socket.assigns.selected_products) do
      {:error, "No products selected"}
    else
      line_items =
        Enum.map(socket.assigns.selected_products, fn product_id ->
          # Fetch the price for the product
          with {:ok, product} <- Stripe.Product.retrieve(product_id),
               price_id when is_binary(price_id) <- get_default_price_id(product) do
            quantity = ceil(socket.assigns.num_users / 10)

            %{
              price: price_id,
              quantity: quantity
            }
          else
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      if Enum.empty?(line_items) do
        {:error, "Failed to fetch prices for selected products"}
      else
        host_uri = socket.host_uri

        base_url =
          "#{host_uri.scheme}://#{host_uri.host}" <>
            if host_uri.port, do: ":#{host_uri.port}", else: ""

        Stripe.Checkout.Session.create(%{
          payment_method_types: [:card],
          line_items: line_items,
          mode: :subscription,
          success_url: "#{base_url}/subscribe/success?session_id={CHECKOUT_SESSION_ID}",
          cancel_url: "#{base_url}/subscribe",
          allow_promotion_codes: true,
          billing_address_collection: :required,
          payment_method_collection: :always,
          customer_email: socket.assigns.current_user.email
        })
      end
    end
  end

  # Helper function to get the default price ID from a product
  defp get_default_price_id(product) do
    case product do
      %{default_price: price_id} when is_binary(price_id) -> price_id
      %{default_price: %{id: price_id}} when is_binary(price_id) -> price_id
      _ -> nil
    end
  end
end
