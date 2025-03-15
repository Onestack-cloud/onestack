defmodule OnestackWeb.Admin.InviteFormComponent do
  use OnestackWeb, :live_component
  alias Onestack.{Accounts, StripeCache, Teams}

  @impl true
  def update(assigns, socket) do
    changeset = %{}
    invited_emails = assigns[:invited_emails] || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:invited_emails, invited_emails)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
      phx-hook="ClearInput"
      id="invite-form-container"
    >
      <.header class="text-gray-900 dark:text-gray-100">
        <%= @title %>
      </.header>

      <.simple_form
        for={@form}
        id="invite-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="send-invites"
        onkeydown="if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); return false; }"
      >
        <.input
          field={@form[:invited_emails]}
          type="email"
          label="Email Addresses"
          phx-keydown="add_email"
          phx-key="Enter"
          phx-window-keydown="add_email"
          value=""
          placeholder="Enter email address and press Enter"
        />
        <div class="mt-2 flex flex-wrap gap-2">
          <%= for email <- @invited_emails do %>
            <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
              <%= email %>
              <button
                type="button"
                phx-click="remove_email"
                phx-value-email={email}
                class="ml-1 text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-200 hover:cursor-pointer"
              >
                &times;
              </button>
            </span>
          <% end %>
        </div>

        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={[{"Member", "member"}]}
          disabled
          class="appearance-none bg-gray-100 dark:bg-gray-700 cursor-not-allowed text-gray-500 dark:text-gray-400"
        />
        <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          More roles coming soon
        </p>

        <.input
          field={@form[:teams_and_groups]}
          type="select"
          label="Teams & Groups"
          options={[{"All Teams", "all_teams"}]}
          disabled
          class="appearance-none bg-gray-100 dark:bg-gray-700 cursor-not-allowed text-gray-500 dark:text-gray-400"
        />
        <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          Create and manage custom teams - coming soon
        </p>

        <:actions>
          <.button phx-disable-with="Sending...">Send Invites</.button>
          <.button
            type="button"
            phx-click={JS.patch(@patch)}
            class="bg-transparent hover:bg-gray-100 text-blue-600 dark:text-blue-400 border border-blue-600 dark:border-blue-400 dark:hover:bg-gray-700"
          >
            Cancel
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("add_email", %{"key" => "Enter", "value" => email}, socket) do
    if email != "" do
      {:noreply,
       socket
       |> update(:invited_emails, fn emails -> [email | emails || []] end)
       |> push_event("clear-input", %{selector: "#invite-form_invited_emails"})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", _target, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_email", %{"email" => email}, socket) do
    {:noreply,
     update(socket, :invited_emails, fn emails ->
       Enum.reject(emails, fn e -> e == email end)
     end)}
  end

  @impl true
  def handle_event("send-invites", _params, socket) do
    invited_emails = socket.assigns.invited_emails
    admin_user = socket.assigns.current_user
    combined_customer = get_combined_customer(admin_user.email)

    if Enum.empty?(invited_emails) do
      {:noreply, socket |> put_flash(:error, "Please add at least one email address")}
    else
      # Process each email and collect results
      results =
        Enum.map(invited_emails, fn email ->
          cond do
            !valid_email?(email) ->
              {:error, "Invalid email address: #{email}"}

            true ->
              case handle_member_addition(email, admin_user, combined_customer, socket) do
                {:noreply, %{assigns: %{flash: %{info: msg}}}} -> {:ok, msg}
                {:noreply, %{assigns: %{flash: %{error: msg}}}} -> {:error, msg}
                _ -> {:error, "Unknown error processing #{email}"}
              end
          end
        end)

      # Count successes and failures
      {successes, failures} =
        Enum.split_with(results, fn
          {:ok, _} -> true
          {:error, _} -> false
        end)

      # Prepare flash message
      flash_message =
        case {length(successes), length(failures)} do
          {s, 0} -> {:info, "Successfully sent #{s} invitation(s)"}
          {0, f} -> {:error, "Failed to send #{f} invitation(s)"}
          {s, f} -> {:warning, "Sent #{s} invitation(s), failed to send #{f}"}
        end

      # Broadcast the team update to refresh the UI
      Phoenix.PubSub.broadcast(
        Onestack.PubSub,
        "team:#{admin_user.id}",
        {:team_updated}
      )
      
      # Broadcast the flash message
      Phoenix.PubSub.broadcast(
        Onestack.PubSub,
        "team:#{admin_user.id}",
        {:invites_sent, flash_message}
      )

      # Close the modal without a full page refresh
      {:noreply,
       socket
       |> put_flash(elem(flash_message, 0), elem(flash_message, 1))
       |> assign(invited_emails: [])
       |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp valid_email?(email) do
    # Basic email validation regex
    email =~ ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$/
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

  defp get_combined_customer(email) do
    StripeCache.list_combined_customers()
    |> Enum.find(fn customer -> customer.email == email end)
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

        # Broadcast the team update to refresh the UI
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "team:#{admin_user.id}",
          {:team_updated}
        )
        
        # Broadcast the flash message
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "team:#{admin_user.id}",
          {:invites_sent, {:info, "Team member added successfully"}}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Team member added successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add team member")}
    end
  end

  defp add_invited_member(recipient_email, admin_user, _combined_customer, socket) do
    # First add the team member
    Teams.add_team_member(admin_user, recipient_email)
    invitation_id = UUID.uuid4()

    # Then create the invitation
    case Teams.create_invitation(%{
           recipient_email: recipient_email,
           admin_email: admin_user.email,
           invitation_id: invitation_id
         }) do
      {:ok, _invitation} ->
        # Send invitation email
        {:ok, _email_result} =
          Onestack.InvitationEmail.send_invitation(
            recipient_email,
            admin_user.email,
            invitation_id
          )

        # Broadcast the team update to refresh the UI
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "team:#{admin_user.id}",
          {:team_updated}
        )
        
        # Broadcast the flash message
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "team:#{admin_user.id}",
          {:invites_sent, {:info, "Invitation sent successfully"}}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create invitation")}
    end
  end
end
