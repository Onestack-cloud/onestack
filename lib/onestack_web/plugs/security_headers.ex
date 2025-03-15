defmodule OnestackWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug to set custom security headers, including Content Security Policy
  with proper configuration for Stripe Elements.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_csp_header()
    |> put_other_security_headers()
  end

  defp put_csp_header(conn) do
    Plug.Conn.put_resp_header(
      conn,
      "content-security-policy",
      "default-src 'self'; " <>
        "script-src 'self' https://js.stripe.com https://m.stripe.network https://checkout.stripe.com https://m.stripe.com https://api.stripe.com 'sha256-5DA+a07wxWmEka9IdoWjSPVHb17Cp5284/lJzfbl8KA=' 'sha256-/5Guo2nzv5n/w6ukZpOBZOtTJBJPSkJ6mhHpnBgm3Ls=' 'unsafe-inline'; " <>
        "connect-src 'self' https://api.stripe.com; " <>
        "frame-src 'self' https://js.stripe.com https://hooks.stripe.com https://checkout.stripe.com https://m.stripe.com; " <>
        "img-src 'self' data: https://*.stripe.com; " <>
        "style-src 'self' 'unsafe-inline'"
    )
  end

  defp put_other_security_headers(conn) do
    conn
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    |> Plug.Conn.put_resp_header("x-frame-options", "SAMEORIGIN")
    |> Plug.Conn.put_resp_header("x-xss-protection", "1; mode=block")
  end
end
