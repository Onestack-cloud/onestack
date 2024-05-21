defmodule Onestack.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :category, :string
      add :closed_source_name, :string
      add :open_source_name, :string
      add :closed_source_user_price, :decimal
      add :open_source_fixed_price, :decimal
      add :usd_to_aud, :decimal
      add :closed_source_currency, :string
      add :open_source_currency, :string
      add :closed_source_user_price_aud, :decimal

      timestamps(type: :utc_datetime)
    end
  end
end
