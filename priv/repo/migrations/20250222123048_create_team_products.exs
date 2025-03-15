defmodule Onestack.Repo.Migrations.CreateTeamProducts do
  use Ecto.Migration

  def change do
    create table(:team_products) do
      add :access_level, :string
      add :team_id, references(:teams, on_delete: :nothing)
      add :product_id, references(:products, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:team_products, [:team_id])
    create index(:team_products, [:product_id])
  end
end
