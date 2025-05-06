defmodule Onestack.Repo do
  use Ecto.Repo,
    otp_app: :onestack,
    adapter: Ecto.Adapters.SQLite3

  # adapter: Ecto.Adapters.Postgres
end
