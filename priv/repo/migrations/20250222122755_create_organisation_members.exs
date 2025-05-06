defmodule Onestack.Repo.Migrations.CreateOrganisationMembers do
  use Ecto.Migration

  def change do
    create table(:organisation_members) do
      add :role, :string
      add :email, :string
      add :organisation_id, references(:organisations, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:organisation_members, [:organisation_id])
    create index(:organisation_members, [:user_id])
  end
end
