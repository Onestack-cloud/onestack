defmodule OnestackWeb.PageController do
  use OnestackWeb, :controller
  alias OnestackWeb.Router.Helpers, as: Routes

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy, page_title: "Privacy Policy")
  end

  def roadmap(conn, _params) do
    render(conn, :roadmap, page_title: "Roadmap")
  end

  def security(conn, _params) do
    render(conn, :security, page_title: "Security")
  end

  def test_land(conn, _params) do
    render(conn, :test_land, page_title: "Test Land")
  end

  def sitemap(conn, _params) do
    # sitemap_path = Routes.static_path(conn,)

    conn
    |> put_resp_content_type("text/xml")
    |> send_file(200, Path.join(:code.priv_dir(:onestack), "static/sitemap/sitemap.xml"))
  end

  def redirect_to_subscribe(conn, _params) do
    redirect(conn, to: ~p"/subscribe")
  end
end
