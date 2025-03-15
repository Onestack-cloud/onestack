defmodule OnestackWeb.URLHelper do
  @doc """
  Returns the main domain URL for Onestack.
  """
  def main_domain do
    host = Application.get_env(:sitemap, :host)

    case host do
      "http://localhost:4000" -> "http://localhost:4000"
      _ -> String.trim_trailing(host, "/")
    end
  end

  @doc """
  Joins the main domain with a path.
  """
  def main_domain_path(path) do
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    host = Application.get_env(:sitemap, :host)

    case host do
      "http://localhost:4000" -> "http://localhost:4000" <> path
      _ -> main_domain() <> path
    end
  end

  @doc """
  Returns a subdomain URL (e.g., feedback.onestack.cloud)
  """
  def subdomain_url(subdomain) do
    host = Application.get_env(:sitemap, :host)

    case host do
      "http://localhost:4000" ->
        "http://#{subdomain}.localhost:4000"

      _ ->
        base_domain =
          host
          |> String.replace_prefix("https://", "")
          |> String.replace_prefix("http://", "")

        "https://#{subdomain}.#{base_domain}"
    end
  end

  @doc """
  Joins the subdomain URL with a path.
  """
  def subdomain_path(subdomain, path) do
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    subdomain_url(subdomain) <> path
  end
end
