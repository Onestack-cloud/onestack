defmodule OnestackWeb.Plugs.RawBodyReader do
  @moduledoc """
  Plug to read and store the raw body for webhook signature verification
  """
  
  def init(opts), do: opts

  def call(conn, _opts) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} ->
        conn
        |> Plug.Conn.assign(:raw_body, body)
        |> Plug.Conn.assign(:body_params, Jason.decode!(body))
      
      {:error, _reason} ->
        conn
    end
  rescue
    _ -> conn
  end
end