defmodule NocoDBClient do
  @moduledoc """
  A simple client to interact with NocoDB API.
  """

  @base_url "https://app.nocodb.com/api/v2/tables/msmxwogygbuqtek/records"
  @headers [
    {"accept", "application/json"},
    {"xc-token", "vf-kOakGvB28J6cWmKLsaBO1kUyEogfYNZ8fufLb"}
  ]

  def fetch_records do
    params = %{
      viewId: "vw4upx9gc6com1gp",
      limit: 25,
      shuffle: 0,
      offset: 0
    }

    url = build_url(@base_url, params)

    case HTTPoison.get(url, @headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, %{status_code: status_code, body: body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp build_url(base_url, params) do
    query_string = URI.encode_query(params)
    "#{base_url}?#{query_string}"
  end
end
