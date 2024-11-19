defmodule Onestack.Repo.Migrations.AddHashColumnsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bcrypt_hash, :string, null: true
      add :argon2id_hash, :string, null: true
      add :pkbdf2_hash, :string, null: true
    end
  end
end
