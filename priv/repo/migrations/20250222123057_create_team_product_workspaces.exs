defmodule Onestack.Repo.Migrations.CreateTeamProductWorkspaces do
  use Ecto.Migration

  def change do
    create table(:team_product_workspaces) do
      add :access_level, :string
      add :team_product_id, references(:team_products, on_delete: :nothing)
      add :workspace_id, references(:workspaces, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:team_product_workspaces, [:team_product_id])
    create index(:team_product_workspaces, [:workspace_id])
  end
end
