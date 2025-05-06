defmodule Onestack.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:matrix_users) do
      add :email, :string
      add :matrix_id, :string
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end
  end
end
