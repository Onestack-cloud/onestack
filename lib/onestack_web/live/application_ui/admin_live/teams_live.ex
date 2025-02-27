# lib/onestack_web/live/admin/members_live.ex
defmodule OnestackWeb.Admin.TeamsLive do
  use OnestackWeb, :live_view
  alias Onestack.{Accounts, Stats, Teams, StripeCache}
  use OnestackWeb.AssignCurrentPath

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      # Subscribe to member updates
    end

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Accounts.get_user_by_session_token(user_token)
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Onestack.PubSub, "team:#{current_user.id}")
    end

    team_members = Teams.list_team_members(current_user)

    stats = Stats.get_user_stats(current_user)
    # Get pending invitations for the current user's email
    pending_invitations =
      Onestack.Teams.list_pending_invitations()
      |> Enum.filter(fn invitation -> invitation.admin_email == current_user.email end)

    {:ok,
     assign(socket,
       page_title: "Team Members",
       selected_department: "all",
       search: "",
       show_invite_modal: false,
       show_member_details: nil,
       view: "grid",
       selected_members: MapSet.new(),
       show_bulk_actions: false,
       stats: stats,
       pending_invitations_count: length(pending_invitations),
       current_user: current_user,
       invited_emails: [],
       team_members: team_members,
       num_users: calculate_num_users(team_members)
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, current_path: URI.parse(uri).path)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Invite users")
    |> assign(:show_invite_modal, true)
    |> assign(current_path: "")
  end

  def apply_action(socket, _action, _params) do
    socket
    |> assign(:page_title, "Team Members")
    |> assign(:show_invite_modal, false)
  end

  # Helper functions
  defp stat_background_color(type) do
    case type do
      :primary -> "bg-blue-50 dark:bg-blue-900/30"
      :success -> "bg-green-50 dark:bg-green-900/30"
      :warning -> "bg-amber-50 dark:bg-amber-900/30"
      :info -> "bg-purple-50 dark:bg-purple-900/30"
      _ -> "bg-gray-50 dark:bg-gray-900/30"
    end
  end

  defp stat_icon_color(type) do
    case type do
      :primary -> "text-blue-600 dark:text-blue-400"
      :success -> "text-green-600 dark:text-green-400"
      :warning -> "text-amber-600 dark:text-amber-400"
      :info -> "text-purple-600 dark:text-purple-400"
      _ -> "text-gray-600 dark:text-gray-400"
    end
  end

  defp role_colors(role) do
    case role do
      "Admin" -> "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400"
      "Member" -> "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"
      "Guest" -> "bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400"
      _ -> "bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400"
    end
  end

  # Event handlers
  @impl true
  def handle_event("toggle-invite-modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: !socket.assigns.show_invite_modal)}
  end

  @impl true
  def handle_info({:send_invites, emails}, socket) do
    # Add your invite sending logic here
    {:noreply, assign(socket, show_invite_modal: false)}
  end

  def handle_event("set-view", %{"view" => view}, socket) do
    {:noreply, assign(socket, view: view)}
  end

  def handle_event("filter-department", %{"department" => department}, socket) do
    {:noreply, assign(socket, selected_department: department)}
  end

  def handle_event("search", %{"value" => search}, socket) do
    {:noreply, assign(socket, search: search)}
  end

  def handle_event("toggle-member", %{"id" => id}, socket) do
    member_id = String.to_integer(id)

    selected_members =
      if MapSet.member?(socket.assigns.selected_members, member_id) do
        MapSet.delete(socket.assigns.selected_members, member_id)
      else
        MapSet.put(socket.assigns.selected_members, member_id)
      end

    {:noreply, assign(socket, selected_members: selected_members)}
  end

  def handle_event("clear-selection", _, socket) do
    {:noreply, assign(socket, selected_members: MapSet.new())}
  end

  def handle_event("remove_member", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user

    # First try to remove any pending invitation
    invitation_removed = false
    case Teams.get_pending_invitation_by_email(email) do
      %Teams.Invitation{} = invitation -> 
        Teams.delete_invitation(invitation)
        invitation_removed = true
      nil -> :ok
    end

    # Then remove the team member
    case Teams.remove_team_member(current_user, email) do
      {:ok, _team} ->
        product_names =
          get_product_names(socket.assigns.stats.stripe_product_ids)

        Onestack.MemberManager.remove_member(
          email,
          product_names
        )

        updated_team_members = Teams.list_team_members(current_user)
        
        # Get updated pending invitations count if an invitation was removed
        updated_pending_invitations_count = socket.assigns.pending_invitations_count
        if invitation_removed do
          pending_invitations =
            Onestack.Teams.list_pending_invitations()
            |> Enum.filter(fn invitation -> invitation.admin_email == current_user.email end)
          
          updated_pending_invitations_count = length(pending_invitations)
        end

        # Broadcast the update to all subscribers
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "team:#{current_user.id}",
          {:team_updated}
        )
        
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "team:#{current_user.id}",
          {:member_removed, email}
        )

        {:noreply,
         socket
         |> assign(team_members: updated_team_members)
         |> assign(num_users: calculate_num_users(updated_team_members))
         |> assign(pending_invitations_count: updated_pending_invitations_count)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Team member not found")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove team member")}
    end
  end

  def handle_event("add_email", %{"key" => "Enter", "value" => email}, socket) do
    # Validate email format
    case validate_email(email) do
      {:ok, validated_email} ->
        # Only add if not already in the list
        if validated_email in socket.assigns.invited_emails do
          {:noreply,
           socket
           |> put_flash(:info, "Email address is already in the list")}
        else
          {:noreply,
           socket
           |> assign(invited_emails: [validated_email | socket.assigns.invited_emails])
           |> put_flash(:info, "Email address added successfully")}
        end

      {:error, message} ->
        {:noreply,
         socket
         |> put_flash(:error, message)}
    end
  end

  def handle_member_addition(team_member_email, admin_user, combined_customer, socket) do
    case Accounts.get_user_by_email(team_member_email) do
      # Existing user flow
      %Accounts.User{} = team_member ->
        add_existing_member(team_member, admin_user, combined_customer, socket)

      # New user flow
      nil ->
        add_invited_member(team_member_email, admin_user, combined_customer, socket)
    end
  end

  @impl true
  def handle_info({:send_invites, %{invited_emails_list: invited_emails}}, socket) do
    # Iterate through invited emails and handle member addition for each
    Enum.reduce(invited_emails, socket, fn email, acc_socket ->
      handle_member_addition(
        email,
        socket.assigns.current_user,
        socket.assigns.combined_customer,
        acc_socket
      )
    end)
    |> then(fn updated_socket ->
      {:noreply,
       updated_socket
       |> put_flash(:info, "#{length(invited_emails)} invites sent successfully")
       |> push_patch(to: ~p"/admin/teams")}
    end)
  end

  def handle_info({:team_updated}, socket) do
    current_user = socket.assigns.current_user
    team_members = Teams.list_team_members(current_user)
    
    # Get updated pending invitations count
    pending_invitations =
      Onestack.Teams.list_pending_invitations()
      |> Enum.filter(fn invitation -> invitation.admin_email == current_user.email end)
    
    {:noreply,
     socket
     |> assign(team_members: team_members)
     |> assign(num_users: calculate_num_users(team_members))
     |> assign(pending_invitations_count: length(pending_invitations))}
  end

  def handle_info({:member_removed, email}, socket) do
    {:noreply, 
     socket 
     |> put_flash(:info, "Team member #{email} has been removed successfully")}
  end

  def handle_info({:invites_sent, message}, socket) do
    {:noreply, 
     socket 
     |> put_flash(elem(message, 0), elem(message, 1))}
  end

  # Email validation constants
  # Maximum length as per RFC 5321
  @max_email_length 254
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  defp validate_email(email) do
    cond do
      String.length(email) > @max_email_length ->
        {:error, "Email address is too long (maximum is #{@max_email_length} characters)"}

      String.length(email) == 0 ->
        {:error, "Email address cannot be empty"}

      !Regex.match?(@email_regex, email) ->
        {:error, "Please enter a valid email address"}

      true ->
        {:ok, email}
    end
  end

  defp calculate_num_users(team_members) do
    max(1, length(team_members))
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
end
