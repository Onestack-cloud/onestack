defmodule Onestack.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams) do
      add :members, {:array, :string}, null: false
      add :products, {:array, :string}, null: false
      # Assuming this should be a string
      add :admin_email, :string, null: false

      # This should be a separate line
      timestamps(type: :utc_datetime)
    end

    # Add an index for the admin_email foreign key
    create index(:teams, [:admin_email])

    # Optionally, add a GIN index for faster array operations
    create index(:teams, [:members])
    create index(:teams, [:products])
  end
end
