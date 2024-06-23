defmodule OnestackWeb.PageController do
  use OnestackWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def security(conn, _params) do
    render(conn, :security)
  end
end
