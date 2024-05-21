defmodule Onestack.Repo do
  use Ecto.Repo,
    otp_app: :onestack,
    adapter: Ecto.Adapters.SQLite3
end
