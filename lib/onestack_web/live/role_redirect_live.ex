defmodule OnestackWeb.RoleRedirectLive do
  use OnestackWeb, :live_view

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    redirect_path =
      cond do
        # Check if user is a super admin

        # Check if user is an admin
        user && socket.assigns.is_admin ->
          ~p"/admin/products"

        # Regular authenticated user
        user ->
          ~p"/member/products"

        # Fallback for unauthenticated users (should not happen due to ensure_authenticated)
        true ->
          ~p"/"
      end

    {:noreply, push_redirect(socket, to: redirect_path)}
  end

  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
