defmodule OnestackWeb.Sitemap do
  use Sitemap

  def generate do
    create do
      # Get all routes from the router
      OnestackWeb.Router.__routes__()
      |> Enum.filter(&filter_routes/1)
      |> Enum.each(&add_route/1)
    end
  end

  defp filter_routes(route) do
    # Filter out any routes you don't want in the sitemap
    # For example, only include GET requests and exclude certain paths
    # Exclude routes with parameters
    route.verb == :get and
      not String.starts_with?(route.path, "/admin") and
      not String.contains?(route.path, ":")
  end

  defp add_route(route) do
    # Remove route parameters
    path = String.replace(route.path, ~r/\/:[\w-]+/, "")
    add path, priority: 0.5, changefreq: "daily"
  end
end
