defmodule Onestack.HTTPClientCompatibilityTest do
  use ExUnit.Case, async: true

  defmodule ResponsePlug do
    import Plug.Conn

    def init(options), do: options

    def call(%{request_path: "/echo"} = conn, _options) do
      {:ok, body, conn} = read_body(conn)
      send_resp(conn, 201, body)
    end

    def call(conn, _options), do: send_resp(conn, 409, "synthetic conflict")
  end

  setup do
    listener =
      start_supervised!({Bandit, plug: ResponsePlug, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    %{url: "http://127.0.0.1:#{port}"}
  end

  test "POST retains the response body and status contract", %{url: url} do
    assert {:ok, %HTTPoison.Response{status_code: 201, body: "synthetic request"}} =
             HTTPoison.post(url <> "/echo", "synthetic request")
  end

  test "non-success responses retain their body for existing caller error handling", %{url: url} do
    assert {:ok, %HTTPoison.Response{status_code: 409, body: "synthetic conflict"}} =
             HTTPoison.post(url <> "/conflict", "synthetic request")
  end

  test "connection failures retain the HTTPoison error struct" do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)

    assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
             HTTPoison.post("http://127.0.0.1:#{port}", "synthetic request", [], timeout: 1_000)
  end
end
