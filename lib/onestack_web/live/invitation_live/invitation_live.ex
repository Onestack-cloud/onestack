defmodule OnestackWeb.InvitationLive do
  use OnestackWeb, :live_view
  alias Onestack.MemberManager

  def mount(%{"token" => "test"}, _session, socket) do
    # {:ok, assign(socket)}
  end

  def mount(%{"token" => token}, _session, socket) do
    # Fetch and clear the results
  end

  # defp error_message(:not_found), do: "Invalid invitation link."
  # defp error_message(:expired), do: "This invitation has expired."
  # defp error_message(:already_used), do: "This invitation has already been used."
end
