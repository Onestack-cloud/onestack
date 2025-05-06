defmodule Onestack.Repo.Migrations.CreateActivityLogs do
  use Ecto.Migration

  def change do
    create table(:activity_logs) do
      add :action, :string
      add :entity_type, :string
      add :entity_id, :integer
      add :changes, :map
      add :user_id, references(:users, on_delete: :nothing)
      add :organisation_id, references(:organisations, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:activity_logs, [:user_id])
    create index(:activity_logs, [:organisation_id])
  end
end
