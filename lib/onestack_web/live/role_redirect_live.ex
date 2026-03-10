defmodule OnestackWeb.RoleRedirectLive do
  use OnestackWeb, :live_view
  alias Onestack.Member.Stats

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    redirect_path =
      cond do
        # Check if user is a super admin

        # Check if user is an admin
        user && socket.assigns.is_admin ->
          ~p"/admin/features"

        # Regular authenticated user
        user ->
          # Check if user has any subscribed products
          stats = Stats.get_user_stats(user)
          
          if Enum.empty?(stats.subscribed_products) do
            # New user with no products - send to onboarding
            ~p"/onboarding"
          else
            # Existing user with products - send to features
            ~p"/member/features"
          end

        # Fallback for unauthenticated users (should not happen due to ensure_authenticated)
        true ->
          ~p"/"
      end

    {:ok, push_navigate(socket, to: redirect_path)}
  end

  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
