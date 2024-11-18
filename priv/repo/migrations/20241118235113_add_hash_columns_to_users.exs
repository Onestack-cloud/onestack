defmodule Onestack.Repo.Migrations.AddHashColumnsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bcrypt_hash, :string, null: false
      add :argon2id_hash, :string, null: false
      add :pkbdf2_hash, :string, null: false
    end
  end
end
