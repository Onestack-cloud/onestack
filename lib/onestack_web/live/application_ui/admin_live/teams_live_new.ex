# lib/onestack_web/live/admin/members_live.ex
defmodule OnestackWeb.Admin.TeamsLiveNew do
  use OnestackWeb, :live_view
  alias Onestack.{Accounts, Stats}
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

    stats = Stats.get_user_stats(current_user)
    # Get pending invitations for the current user's email
    pending_invitations =
      Onestack.Teams.list_pending_invitations()
      |> Enum.filter(fn invitation -> invitation.admin_email == current_user.email end)

    {:ok,
     assign(socket,
       page_title: "Team Members",
       members: get_dummy_members(),
       departments: get_dummy_departments(),
       roles: get_dummy_roles(),
       selected_department: "all",
       search: "",
       show_invite_modal: false,
       show_member_details: nil,
       view: "grid",
       selected_members: MapSet.new(),
       show_bulk_actions: false,
       stats: stats,
       pending_invitations_count: length(pending_invitations)
     )}
  end

  defp get_dummy_members do
    [
      %{
        id: 1,
        name: "Sarah Chen",
        email: "sarah@example.com",
        avatar_url: "https://i.pravatar.cc/150?img=1",
        role: %{name: "Admin", admin: true},
        department: "Engineering",
        status: :online,
        products: [
          %{name: "GitHub", icon: "hero-code-bracket"},
          %{name: "Slack", icon: "hero-chat-bubble-left-right"},
          %{name: "Figma", icon: "hero-pencil"},
          %{name: "Notion", icon: "hero-document"}
        ],
        last_active: "2 minutes ago"
      },
      %{
        id: 2,
        name: "Michael Torres",
        email: "michael@example.com",
        avatar_url: "https://i.pravatar.cc/150?img=2",
        role: %{name: "Member", admin: false},
        department: "Design",
        status: :online,
        products: [
          %{name: "Figma", icon: "hero-pencil"},
          %{name: "Slack", icon: "hero-chat-bubble-left-right"}
        ],
        last_active: "5 minutes ago"
      }
      # Add more dummy members...
    ]
  end

  defp get_dummy_departments do
    [
      %{id: "all", name: "All Departments"},
      %{id: "engineering", name: "Engineering"},
      %{id: "design", name: "Design"},
      %{id: "marketing", name: "Marketing"},
      %{id: "sales", name: "Sales"}
    ]
  end

  defp get_dummy_roles do
    [
      %{id: "admin", name: "Admin"},
      %{id: "member", name: "Member"},
      %{id: "guest", name: "Guest"}
    ]
  end

  defp get_dummy_products do
    [
      %{id: 1, name: "GitHub Enterprise"},
      %{id: 2, name: "Slack"},
      %{id: 3, name: "Figma"},
      %{id: 4, name: "Notion"}
    ]
  end

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

  def handle_event("send-invites", _, socket) do
    # Handle sending invites
    {:noreply, socket}
  end
end
