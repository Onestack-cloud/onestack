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

    team_members =
      if current_user do
        direct_members = Teams.list_team_members(current_user)

        if direct_members == [] do
          # Check if user is member of any teams
          team =
            Enum.find(Teams.list_teams(), fn t ->
              current_user.email in t.members
            end)

          case team do
            nil -> []
            team -> team.members
          end
        else
          direct_members
        end
      else
        []
      end

    stripe_products =
      if current_user do
        case Enum.find(combined_customers, fn customer -> customer.email == current_user.email end) do
          nil -> []
          customer -> customer.products
        end
      else
        []
      end

    view_to_show =
      cond do
        is_nil(current_user) ->
          :no_subscription

        stripe_products != [] && Enum.member?(team_members, current_user.email) ->
          :has_subscription_and_is_admin

        stripe_products == [] && Enum.member?(team_members, current_user.email) ->
          :has_subscription_and_is_user

        true ->
          IO.puts("none of the conditions were met")
          :no_subscription
      end

    user_products =
      case view_to_show do
        :has_subscription_and_is_user ->
          team =
            Enum.find(Teams.list_teams(), fn t ->
              current_user.email in t.members
            end)

          case team do
            nil ->
              []

            team ->
              case Enum.find(combined_customers, fn customer ->
                     customer.email == team.admin_email
                   end) do
                nil -> []
                customer -> customer.products
              end
          end

        _ ->
          stripe_products
      end

    num_users = calculate_num_users(team_members)
    has_subscription = user_products != []

    upcoming_invoice =
      if view_to_show == :has_subscription_and_is_admin do
        stripe_customer =
          Enum.find(combined_customers, fn customer -> customer.email == current_user.email end)

        case Onestack.StripeCache.get_upcoming_invoice(stripe_customer.subscription_id) do
          nil ->
            {:error, "Subscription not found"}

          subscription ->
            subscription
        end
      end

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
      |> assign(upcoming_invoice: upcoming_invoice)
      |> assign(view_to_show: view_to_show)

    # IO.inspect(socket)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="py-8 lg:py-20 min-h-screen" id="subscribe">
      <%= if @current_user && (!@current_user.bcrypt_hash || @current_user.bcrypt_hash == "") do %>
        <div class="container mx-auto px-4 mb-4">
          <div class="bg-yellow-50 dark:bg-yellow-900/50 border-l-4 border-yellow-400 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-yellow-400" />
              </div>
              <div class="ml-3">
                <p class="text-sm text-yellow-700 dark:text-yellow-200">
                  Please reset your password to migrate to the new Onestack single password system. Log out and use the "Forgot Password" option to set a new password.
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      <div class="container mx-auto px-4">
        <%= cond do %>
          <% @view_to_show == :has_subscription_and_is_admin -> %>
            <.live_component
              module={OnestackWeb.SubscribeLive.HasSubscriptionAndIsAdmin}
              id="has-subscription-and-is-admin"
              {assigns}
            />
          <% @view_to_show == :has_subscription_and_is_user -> %>
            <.live_component
              module={OnestackWeb.SubscribeLive.HasSubscriptionAndIsUser}
              id="has-subscription-and-is-user"
              {assigns}
            />
          <% @view_to_show == :no_subscription -> %>
            <.live_component
              module={OnestackWeb.SubscribeLive.NoSubscription}
              id="no-subscription"
              {assigns}
            />
        <% end %>
      </div>
    </section>
    """
  end

  defp calculate_num_users(team_members) do
    max(1, length(team_members))
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

  def handle_event("set_num_users", %{"num_users" => num_users}, socket) do
    {:noreply, assign(socket, num_users: String.to_integer(num_users))}
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

  def handle_event("add_member", %{"email" => team_member_email}, socket) do
    admin_user = socket.assigns.current_user
    combined_customer = get_combined_customer(admin_user.email)

    cond do
      !valid_email?(team_member_email) ->
        {:noreply, put_flash(socket, :error, "Invalid email address")}

      true ->
        handle_member_addition(team_member_email, admin_user, combined_customer, socket)
    end
  end

  defp handle_member_addition(team_member_email, admin_user, combined_customer, socket) do
    case Accounts.get_user_by_email(team_member_email) do
      # Existing user flow
      %Accounts.User{} = team_member ->
        add_existing_member(team_member, admin_user, combined_customer, socket)

      # New user flow
      nil ->
        add_invited_member(team_member_email, admin_user, combined_customer, socket)
    end
  end

  defp add_existing_member(team_member, admin_user, combined_customer, socket) do
    case Teams.add_team_member(
           admin_user,
           team_member.email,
           combined_customer.products
         ) do
      {:ok, _team} ->
        product_names =
          get_product_names(socket.assigns.selected_products)

        # Send welcome email to existing user
        # TODO: Create welcome email for existing Onestack users
        # {:ok, _email_result} = Emails.send_team_welcome_email(admin_user, current_user, product_names)
        # Process member addition
        {:ok, _job_id} = Onestack.MemberManager.add_member(team_member.email, product_names)

        updated_team_members = Teams.list_team_members(team_member)

        {:noreply,
         socket
         |> assign(team_members: updated_team_members)
         |> assign(num_users: calculate_num_users(updated_team_members))
         |> put_flash(:info, "Team member added successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add team member")}
    end
  end

  defp add_invited_member(recipient_email, admin_user, _combined_customer, socket) do
    Teams.add_team_member(admin_user, recipient_email)
    invitation_id = UUID.uuid4()

    case Teams.create_invitation(%{
           recipient_email: recipient_email,
           admin_email: admin_user.email,
           invitation_id: invitation_id
         }) do
      {:ok, _invitation} ->
        # product_names =
        #   get_product_names(socket.assigns.selected_products)

        # Send invitation email

        {:ok, _email_result} =
          Onestack.InvitationEmail.send_invitation(
            recipient_email,
            admin_user.email,
            invitation_id
          )

        updated_team_members = Teams.list_team_members(admin_user)

        {:noreply,
         socket
         |> assign(team_members: updated_team_members)
         |> assign(num_users: calculate_num_users(updated_team_members))
         |> put_flash(:info, "Invitation sent successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create invitation")}
    end
  end

  def handle_event("remove_member", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user

    case Teams.remove_team_member(current_user, email) do
      {:ok, _team} ->
        product_names =
          get_product_names(socket.assigns.selected_products)

        Onestack.MemberManager.remove_member(
          email,
          product_names
        )

        updated_team_members = Teams.list_team_members(current_user)

        {:noreply,
         socket
         |> assign(team_members: Teams.list_team_members(current_user))
         |> assign(num_users: calculate_num_users(updated_team_members))
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
        # This is the last product and we're removing it -> cancel subscription
        # Remove all members access and delete team
        send(self(), {:cancel_subscription})
        product = Enum.find(StripeCache.list_products(), &(&1.id == product_id))
        product_name = product && product.name
        team_members = Teams.list_team_members(%{email: socket.assigns.current_user.email})

        Enum.each(team_members, fn member ->
          Onestack.MemberManager.remove_member(member, [product_name])
        end)

        Teams.delete_team(Teams.get_team_by_admin(%{email: socket.assigns.current_user.email}))

        {:noreply, assign(socket, updating: true, view_to_show: :no_subscription)}

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

  @spec get_product_names([List.t()]) :: [List.t()]
  def get_product_names(product_ids) do
    stripe_products = StripeCache.list_products()

    product_map =
      Enum.reduce(stripe_products, %{}, fn product, acc ->
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
      {:ok, %{subscription: _subscription_id} = _updated_item} ->
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
        Onestack.StripeCache.delete_subscription_from_cache(combined_customer.subscription_id)
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
    team = Teams.get_team_by_admin(%{email: admin_email})

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
          product_name = product && String.downcase(product.name)

          Onestack.Teams.update_team(team, %{products: [product_name]})

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
          product_name = product && String.downcase(product.name)

          Enum.each(team_members, fn member ->
            Onestack.MemberManager.remove_member(member, [product_name])
          end)

          Onestack.Teams.update_team(team, %{products: List.delete(team.products, product_name)})

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
      user_email = socket.assigns.current_user.email

      customer_params =
        case Stripe.Customer.list(%{email: user_email, limit: 1}) do
          {:ok, %{data: [%{id: customer_id} | _]}} ->
            # Existing customer found, use their ID
            %{customer: customer_id}

          {:ok, %{data: []}} ->
            # No existing customer, use email
            %{customer_email: user_email}

          {:error, _error} ->
            # Handle Stripe API error by falling back to email
            %{customer_email: user_email}
        end

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
          customer_email: socket.assigns.current_user.email,
          subscription_data: %{
            trial_period_days: 7
          }
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
