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

  def roadmap(conn, _params) do
    render(conn, :roadmap)
  end

  def security(conn, _params) do
    render(conn, :security)
  end

  def test_land(conn, _params) do
    render(conn, :test_land)
  end

  def redirect_to_subscribe(conn, _params) do
    redirect(conn, to: ~p"/subscribe")
  end
end
